INTERFACE zif_ai_tool
  PUBLIC.

  TYPES:
    BEGIN OF ty_result,
      xml_payload      TYPE string,     " <code_modified>/<code_example>/... envelope
      save_required    TYPE abap_bool,  " runner must trigger confirm + save afterwards
      object_type      TYPE string,     " filled when save_required = 'X'
      object_name      TYPE string,     " filled when save_required = 'X'
      original_source  TYPE string,     " source before changes (for diff review)
      final_source     TYPE string,     " complete merged source ready to save
      error_text       TYPE string,     " filled when execution failed
    END OF ty_result.

  " Dependency injection - called once by the factory after CREATE OBJECT
  METHODS init
    IMPORTING
      !io_context TYPE REF TO zcl_ai_tool_context.

  " Self-description: tool name as the LLM sees it ('read_sap_object', ...)
  METHODS get_tool_name
    RETURNING VALUE(rv_name) TYPE string.

  " Allows disabling a tool without deleting the class
  METHODS is_active
    RETURNING VALUE(rv_active) TYPE abap_bool.

  " OpenAI function definition - reads <tool_name>.json from the agents folder
  METHODS get_schema
    RETURNING VALUE(rv_schema) TYPE string.

  " Prompt fragment for this tool - reads <tool_name>.md from the agents folder.
  " Assembled into the system prompt by the factory, so a tool that is not
  " installed contributes neither schema (JSON) nor prompt text.
  METHODS get_prompt_fragment
    RETURNING VALUE(rv_fragment) TYPE string.

  " Execution. i_arguments = raw JSON arguments string from the LLM tool call
  METHODS execute
    IMPORTING
      !i_arguments     TYPE string
      !i_context       TYPE string OPTIONAL
    RETURNING VALUE(rs_result) TYPE ty_result.

ENDINTERFACE.
