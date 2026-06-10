# New Tool Architecture: From Proto Tags to OpenAI Function Calling

Design document for migrating the agent system from string-based proto tags
(`{AGENT:CODE_SEARCH PROG Z_TEST}`) to real OpenAI function calling with a
plugin-style tool architecture in ABAP.

---

## 1. Problem with the Current Design

### Current flow

```
USER PROMPT
    -> LANGUAGE_DETECTOR (detect answer language)
    -> OBJECT_DETECTOR   (replace object mentions with {AGENT:...} tags)
    -> TASK_ORCHESTRATOR (LLM returns JSON with target_tool enum)
    -> ZCL_TASK_PLANNER  (converts JSON back into proto-tag strings)
    -> Runner parses string tags and executes
```

### Issues

- Proto tags are plain strings: no typing, no validation, no parameters beyond
  object type + name.
- `target_tool` enum (`ZCL_AI_TOOL=>READ/SAVE/REVIEW/DELETE/NONE`) is a
  pseudo-tool, not a real function-calling contract.
- The `CHANGES:YES/NO` marker carries almost no information (what changed?
  created or modified? does it need saving?).
- Hard to extend: adding a tool means touching prompts, planner CASE branches,
  and the runner.

### Current tool inventory (found in AGENTS/*.md and ABAP sources)

- Tools (task_orchestrator.JSON): `ZCL_AI_TOOL=>READ`, `=>SAVE`, `=>REVIEW`,
  `=>DELETE`, `NONE`
- Proto tags (object_detector.md): `{AGENT:CODE_SEARCH ...}`,
  `{AGENT:CREATE_OBJECT ...}`
- Agents (zcl_ai_agents_prompts constants): OBJECT_DETECTOR, TASK_ORCHESTRATOR,
  LANGUAGE_DETECTOR, CODE_SEARCH, CODE_CHANGE, CODE_REVIEW, DATA_SEARCH,
  CREATE_OBJECT, AGENT_SAVE, CODE_EXTRACT, CLASS_EXTRACT, CODE_DIFF,
  CODE_READER, CLASS_PROCESSOR, PROG_PROCESSOR, DELETE_OBJECT, FINAL

---

## 2. Target Architecture Overview

Three layers, each with its own storage:

```
Layer 1: JSON (contract for the LLM)
  <tool_name>.json - OpenAI function definition (name + parameters schema).
  The LLM never sees ABAP class names.

Layer 2: MD (prompt instruction)
  <tool_name>.md - behavioral rules and output format for that tool.

Layer 3: ABAP (implementation)
  ZIF_AI_TOOL interface + one class per tool + self-building factory registry.
```

### Max 5 tools per LLM call (orchestration levels)

Recommendation: never give the LLM more than ~5 tools at once. Therefore the
flow is split into decision levels:

- **Level 1 - route (5 tools):** detect_and_route, read_sap_object,
  modify_sap_object, review_sap_code, delete_sap_object
- **Level 2 - specialize (per branch, <=5 tools):** e.g. for MODIFY:
  class_processor, prog_processor, create_new_class, create_new_program,
  generic_code_change
- **Level 3 - execution:** ABAP classes do the real work (read, merge, save).
- **Level 4 - format:** FINAL agent formats the answer for the user.

### Example flow: "Add parameter IV_NAME to method CALCULATE of class ZCL_MATH"

1. Level 1: LLM picks `modify_sap_object` (CLAS ZCL_MATH).
2. Pre-step: `read_sap_object` fetches current class source (READ before SAVE).
3. Level 2/3: `class_processor` is called with the source + action; it returns
   changed XML blocks (section + method) which are merged via
   `ZCL_CODE_ANSWER_TOOLS=>MERGE_CLASS_PARTS`, confirmed, and saved.
4. Level 4: FINAL agent formats the user-facing answer.

Roughly 4 LLM calls, each with a small focused toolset.

---

## 3. Structured XML Output (replaces CHANGES:YES/NO)

The legacy `CHANGES:YES` flag is replaced by typed pseudo-XML envelopes with
metadata. Seven envelope types:

```xml
<!-- 1. Modification of an existing object -->
<code_modified type="CLAS|PROG|METH|FUNC" name="..." version="1.0">
  <change_summary>...</change_summary>
  <public_section>...</public_section>
  <method name="...">...</method>
  <metadata>
    <action>method_added|method_deleted|method_signature_changed|code_refactored|bug_fixed</action>
    <modified_sections>...</modified_sections>
    <modified_methods>...</modified_methods>
    <new_parameters>...</new_parameters>
    <save_to_object>true</save_to_object>
    <requires_review>optional</requires_review>
    <breaking_changes>false</breaking_changes>
  </metadata>
</code_modified>

<!-- 2. Creation of a new object -->
<code_created type="CLAS|PROG" name="..." version="1.0">
  <new_object_summary>...</new_object_summary>
  <full_source>...</full_source>
  <metadata>
    <save_to_object>true</save_to_object>
    <requires_review>optional</requires_review>
  </metadata>
</code_created>

<!-- 3. Deletion -->
<code_deleted type="CLAS|PROG" name="..." version="1.0">
  <deletion_reason>...</deletion_reason>
  <metadata>
    <save_to_object>true</save_to_object>
    <requires_review>true</requires_review>
    <confirmed>true</confirmed>
  </metadata>
</code_deleted>

<!-- 4. Analysis / review, no changes -->
<code_analysis type="CLAS|PROG" name="..." version="1.0">
  <analysis_type>code_review|performance_check|security_audit</analysis_type>
  <findings>
    <finding severity="error|warning|info">
      <location>Line 42</location>
      <issue>...</issue>
      <recommendation>...</recommendation>
    </finding>
  </findings>
  <metadata>
    <save_to_object>false</save_to_object>
  </metadata>
</code_analysis>

<!-- 5. Code example - shown only, NOT saved, NO review -->
<code_example type="ABAP_SNIPPET|ABAP_CLASS|ABAP_PATTERN" language="abap" version="1.0">
  <title>...</title>
  <description>...</description>
  <example_code>...</example_code>
  <explanation><point>...</point></explanation>
  <metadata>
    <save_to_object>false</save_to_object>
    <requires_review>false</requires_review>
    <executable>false</executable>
  </metadata>
</code_example>

<!-- 6. Documentation / explanation -->
<code_documentation type="GUIDE|TUTORIAL|EXPLANATION" version="1.0">
  <title>...</title>
  <content>...</content>
  <metadata><save_to_object>false</save_to_object></metadata>
</code_documentation>

<!-- 7. Error diagnosis -->
<error_analysis type="SYNTAX_ERROR|RUNTIME_ERROR|LOGICAL_ERROR" version="1.0">
  <problem_description>...</problem_description>
  <root_cause>...</root_cause>
  <solution>
    <corrected_code>...</corrected_code>
  </solution>
  <metadata><save_to_object>false</save_to_object></metadata>
</error_analysis>
```

### Routing matrix

| Envelope             | save_to_object | requires_review | Where shown          |
|----------------------|----------------|-----------------|----------------------|
| `code_modified`      | yes            | optional        | Editor + dialog      |
| `code_created`       | yes            | optional        | Editor + dialog      |
| `code_deleted`       | yes            | yes             | Confirmation dialog  |
| `code_analysis`      | no             | no              | Result panel         |
| `code_example`       | no             | **no**          | Popup / display only |
| `code_documentation` | no             | no              | Help panel           |
| `error_analysis`     | no             | optional        | Alert dialog         |

Key rule: when the user asks for a code **example** without asking to save it,
the answer is a `<code_example>` - displayed only, never saved, never reviewed.

ABAP-side dispatch is a simple CASE over the root tag of the response.

---

## 4. Tool Plugin Architecture in ABAP

### Interface

```abap
INTERFACE zif_ai_tool PUBLIC.

  TYPES: BEGIN OF ty_result,
           xml_payload   TYPE string,     " <code_modified>... etc.
           save_required TYPE abap_bool,
           error_text    TYPE string,
         END OF ty_result.

  " Self-description: the tool name lives INSIDE the class as a constant
  METHODS get_tool_name
    RETURNING VALUE(rv_name) TYPE string.

  " Allows disabling a tool without deleting the class
  METHODS is_active
    RETURNING VALUE(rv_active) TYPE abap_bool.

  " OpenAI function schema (reads <tool_name>.json)
  METHODS get_schema
    RETURNING VALUE(rv_schema) TYPE string.

  " Execution. i_arguments = raw JSON arguments from the LLM tool call
  METHODS execute
    IMPORTING i_arguments      TYPE string
              i_context        TYPE string OPTIONAL
    RETURNING VALUE(rs_result) TYPE ty_result.

ENDINTERFACE.
```

The interface defines only the public contract. Each tool class can (and
should) have any number of PRIVATE helper methods (parse_arguments,
read_current_source, call_llm_processor, merge_and_confirm, ...). `execute`
acts as a conductor of those private methods.

### One class per tool

Tools have very different weights: READ is a thin wrapper, MODIFY is a whole
pipeline (read -> LLM with class_processor prompt -> parse XML blocks -> merge
-> confirm popup -> save). One class per tool keeps each class small and
independently testable, and prevents a god object.

```
ZIF_AI_TOOL            interface (1 mandatory method: execute)
ZCL_AI_TOOL_FACTORY    registry + get_tool( ) + get_all_tools( )   ~50 lines
ZCL_AITOOL_READ        ~50 lines  (wraps ZCL_AI_CODE_READER)
ZCL_AITOOL_MODIFY      ~300 lines (modification pipeline)
ZCL_AITOOL_REVIEW      ~80 lines  (READ + LLM with code_review.md)
ZCL_AITOOL_DELETE      ~80 lines  (confirmation + deletion)
ZCL_AITOOL_EXAMPLE     ~50 lines  (LLM call, display only, no save)
```

### Tool class skeleton

```abap
CLASS zcl_aitool_read DEFINITION PUBLIC CREATE PUBLIC.
  PUBLIC SECTION.
    INTERFACES zif_ai_tool.
    " THE single binding point: tool name as a constant
    CONSTANTS c_tool_name TYPE string VALUE 'read_sap_object'.
ENDCLASS.

CLASS zcl_aitool_read IMPLEMENTATION.
  METHOD zif_ai_tool~get_tool_name.
    rv_name = c_tool_name.
  ENDMETHOD.
  METHOD zif_ai_tool~is_active.
    rv_active = abap_true.
  ENDMETHOD.
  METHOD zif_ai_tool~get_schema.
    rv_schema = read_file( c_tool_name && '.json' ).  " read_sap_object.json
  ENDMETHOD.
  METHOD zif_ai_tool~execute.
    " calls ZCL_AI_CODE_READER internally
  ENDMETHOD.
ENDCLASS.
```

The constant `c_tool_name` drives everything:

```
c_tool_name = 'read_sap_object'
   |-> get_tool_name( )      -> registry key in the factory
   |-> name in OpenAI tools  -> LLM calls {"name": "read_sap_object"}
   |-> read_sap_object.json  -> parameter schema (class finds it itself)
   '-> read_sap_object.md    -> prompt instruction (optional)
```

### Factory with auto-discovery (no manual registry)

The ABAP class name is an implementation detail. It must NOT leak into JSON,
MD, or the LLM. The mapping tool_name -> class is built automatically:

```abap
CLASS zcl_ai_tool_factory IMPLEMENTATION.

  METHOD class_constructor.
    " Find ALL active classes implementing ZIF_AI_TOOL
    SELECT clsname
      FROM seometarel
      INTO TABLE @DATA(lt_implementers)
      WHERE refclsname = 'ZIF_AI_TOOL'
        AND reltype    = '1'        " interface implementation
        AND version    = '1'.       " active

    LOOP AT lt_implementers INTO DATA(lv_class).
      DATA lo_tool TYPE REF TO zif_ai_tool.
      TRY.
          CREATE OBJECT lo_tool TYPE (lv_class-clsname).
          IF lo_tool->is_active( ) = abap_false.
            CONTINUE.
          ENDIF.
          " duplicate-name guard
          READ TABLE mt_registry TRANSPORTING NO FIELDS
            WITH KEY tool_name = lo_tool->get_tool_name( ).
          IF sy-subrc = 0.
            " log duplicate, do not silently overwrite
            CONTINUE.
          ENDIF.
          APPEND VALUE #( tool_name = lo_tool->get_tool_name( )
                          instance  = lo_tool ) TO mt_registry.
        CATCH cx_sy_create_object_error ##NO_HANDLER.
          " abstract / CREATE PRIVATE / broken class - skip
      ENDTRY.
    ENDLOOP.
  ENDMETHOD.

  METHOD get_tool.
    READ TABLE mt_registry INTO DATA(ls_reg)
      WITH KEY tool_name = i_tool_name.
    IF sy-subrc = 0.
      ro_tool = ls_reg-instance.
    ENDIF.
  ENDMETHOD.

  METHOD get_all_tools.
    " returns the registry; also used to build the OpenAI tools array
    " (each tool contributes get_schema( ))
  ENDMETHOD.

ENDCLASS.
```

Registry resolution at runtime:

```
LLM returns: {"tool_calls":[{"name":"read_sap_object","arguments":"{...}"}]}
    -> factory: READ TABLE mt_registry WITH KEY tool_name = 'read_sap_object'
    -> CREATE OBJECT ... TYPE ('ZCL_AITOOL_READ')   " dynamic instantiation
    -> lo_tool->execute( i_arguments = lv_json_args )
```

### Runner shrinks to a loop

```abap
LOOP AT lt_tool_calls INTO DATA(ls_call).
  DATA(lo_tool) = zcl_ai_tool_factory=>get_tool( ls_call-name ).
  IF lo_tool IS INITIAL.
    " unknown tool - report error back to the LLM
    CONTINUE.
  ENDIF.
  DATA(ls_result) = lo_tool->execute( ls_call-arguments ).
  " result goes back into messages for the next LLM iteration
ENDLOOP.
```

The runner never changes when tools are added.

### Registry options considered

| | Manual registry (name+class) | Class list + get_tool_name() | SEOMETAREL auto-discovery |
|---|---|---|---|
| Factory edit per new tool | name+class pair | 1 line | **none** |
| Where all tools are visible | factory | factory | nowhere (need select / SE24 where-used) |
| Typo detection | runtime, silent | immediate (CREATE OBJECT fails) | impossible |
| Stray classes in registry | no | no | possible -> guarded by is_active( ) |

Decision: **SEOMETAREL auto-discovery + is_active( )**. Single developer,
Z-namespace, no conflicts expected; "create class -> tool appears" convenience
wins. `get_all_tools( )` covers transparency and doubles as the builder for
the OpenAI `tools` array.

Note: ABAP class names are limited to 30 characters - another reason not to
derive class names from tool names by convention.

---

## 5. Adding a New Tool (full checklist)

```
1. Create class ZCL_AITOOL_<X> with INTERFACES zif_ai_tool
   + CONSTANTS c_tool_name (the ONLY manual binding point)
   + implement execute( )
2. Create AGENTS/<tool_name>.json  (OpenAI parameter schema)
3. Create AGENTS/<tool_name>.md    (prompt instruction, optional)
```

Activate the class - the factory discovers it via SEOMETAREL, asks its name,
registers it, and its schema joins the OpenAI tools array. No changes to the
factory, the runner, or any existing tool.

The single discipline to keep manually: **constant name = file names**.
Self-diagnosis: at startup the factory can verify every active tool returns a
non-empty schema and log a warning otherwise.

---

## 6. Components To Build / Change

| Component | Action | Purpose |
|---|---|---|
| `ZIF_AI_TOOL` | create | tool contract |
| `ZCL_AI_TOOL_FACTORY` | create | auto-discovery registry, get_tool, get_all_tools |
| `ZCL_AITOOL_READ/MODIFY/REVIEW/DELETE/EXAMPLE` | create | tool implementations |
| `ZCL_CODE_AI_API` | modify | send `tools` array to OpenAI, parse `tool_calls` |
| `ZCL_CODE_AI_RUNNER` | modify | agentic loop over tool_calls via factory |
| `ZCL_TASK_PLANNER` | retire | replaced by function calling + factory |
| `AGENTS/<tool>.json` per tool | create | OpenAI function schemas |
| Processor prompts (class_processor.md, programs.md, final.md, ...) | modify | output XML envelopes instead of CHANGES:YES |
