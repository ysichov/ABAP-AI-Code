### read_sap_object

Fetches the current source code of an existing SAP object (program, class,
method, function module) straight from the system. It is a direct read tool: it
returns the source as the tool result and never modifies anything.

When to use:
- The user wants to view, describe, explain, document, list or analyse code.
- As a mandatory prerequisite before modify_sap_object for the same object
  (READ before MODIFY).
- To get the LIST of object names for a multi-object review (use a wildcard).
  Do NOT read full source before review_sap_code - that tool reads the source
  itself, so pre-reading only floods the context.

Arguments:
- object_type: one of PROG, CLAS, METH, FUNC, REPS, OTHER.
- object_name: technical name, e.g. 'ZCL_TEST', 'ZCL_TEST=>METHOD_NAME',
  'Z_PROGRAM'. Supports a wildcard pattern to list matching objects
  (e.g. 'ZCL_AITOOL_*') and a comma-separated list to read several objects in one
  call (e.g. 'ZCL_A, ZCL_B, ZCL_C').
- purpose: 'view' or 'analyze' (default 'analyze').
  - Use 'view' ONLY when the user just wants to see/open this exact source and
    expects nothing more - the source is shown as-is and the task ends.
  - Use 'analyze' (or omit) whenever the read is a STEP toward something else:
    a review, a security / vulnerability analysis, an explanation, following the
    object's dependencies, or a read-before-modify. You will keep working after
    the read - do NOT treat the returned source as the final answer.
  - Example: "show me ZCL_TEST" -> purpose 'view'. "review ZCL_TEST and find
    security issues" -> purpose 'analyze', then continue reading the classes it
    uses and produce the analysis.

Notes:
- If the object is not found the tool reports an error - do not retry with a
  guessed name and do not invent source code.
