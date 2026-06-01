CLASS zcl_ai_agents_prompts DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    CONSTANTS:
      c_agent_orchestrator TYPE string VALUE 'ORCHESTRATOR',
      c_agent_code_search  TYPE string VALUE 'CODE_SEARCH',
      c_agent_code_review  TYPE string VALUE 'CODE_REVIEW',
      c_agent_data_search  TYPE string VALUE 'DATA_SEARCH',
      c_agent_create_obj   TYPE string VALUE 'CREATE_OBJECT',
      c_agent_code_reader  TYPE string VALUE 'CODE_READER'.

    CLASS-METHODS get_orchestrator_prompt
      RETURNING VALUE(rv_prompt) TYPE string.

    CLASS-METHODS get_code_agent_prompt
      RETURNING VALUE(rv_prompt) TYPE string.

    CLASS-METHODS get_data_agent_prompt
      RETURNING VALUE(rv_prompt) TYPE string.

    CLASS-METHODS get_code_review_prompt
      RETURNING VALUE(rv_prompt) TYPE string.

    CLASS-METHODS get_create_object_prompt
      RETURNING VALUE(rv_prompt) TYPE string.

    CLASS-METHODS get_code_reader_prompt
      RETURNING VALUE(rv_prompt) TYPE string.

    CLASS-METHODS get_prompt_by_agent
      IMPORTING i_agent           TYPE string
      RETURNING VALUE(rv_prompt)  TYPE string.

  PRIVATE SECTION.
ENDCLASS.

CLASS zcl_ai_agents_prompts IMPLEMENTATION.

  METHOD get_orchestrator_prompt.
    rv_prompt = |You are a Senior ABAP Orchestration AGENT. Answer briefly, without explanations. |
    && |If the user asks for code, \{AGENT:CODE_SEARCH object_type object_name relevant_prompt_part\}.|
             && cl_abap_char_utilities=>newline
             && |If the user asks for method code, use exactly \{AGENT:CODE_SEARCH class_name=>method_name + relevant_prompt_part\}; |
             "&& |do not output class_name=>... method_name=>... as separate fields.|
             && cl_abap_char_utilities=>newline
             "&& |If the user asks for several code objects or methods, put all code-search tasks into one CODE_SEARCH command.|
             "&& cl_abap_char_utilities=>newline
             && |If the prompt asks for more than just showing the code, add that part of the prompt to the answer.|
             && cl_abap_char_utilities=>newline
             && |If requested a code review - \{AGENT:CODE_REVIEW object_type object_name\}.|
             && cl_abap_char_utilities=>newline
             && |If the user asks to show table contents or find some information, |
             && |request the agent:\{AGENT:DATA_SEARCH + the relevant part of the prompt with the request.\}|
             && cl_abap_char_utilities=>newline
             && |If the user asks to create an object: "\{AGENT:CREATE_OBJECT object_type object_name relevant_prompt_part\}" |
             && |Never lose AGENT:CODE_SEARCH|
             && cl_abap_char_utilities=>newline
             && |Never change real code text by AGENT: string insertion, analyse only user free text|
             && cl_abap_char_utilities=>newline
             && |If the request is not relevant to SAP, answer "Not relevant"|
             && cl_abap_char_utilities=>newline
             && |If the request is not described here, answer "Not supported"|
             && cl_abap_char_utilities=>newline
             && cl_abap_char_utilities=>newline
             && |Allowed object types: PROG, CLASS, METH, FM - functional module|
             && cl_abap_char_utilities=>newline
             && cl_abap_char_utilities=>newline
             && |Example: Open the Z_test program and, based on it, create an example calculator program Z_CALC. |
             && |Answer: "\{AGENT:CODE_SEARCH Open the Z_TEST program\} and, based on it, create an example |
             && |calculator program \{AGENT:CREATE_OBJECT program Z_CALC\}.|
             && cl_abap_char_utilities=>newline
             && cl_abap_char_utilities=>newline
             && |Example: delete something - deletion is not supported|.
  ENDMETHOD.

  METHOD get_code_agent_prompt.
    rv_prompt = |You are a Senior ABAP CODE AGENT. You should carefully analyze the prompt and replace part of |
             && |it with the commands described below. Replace in prompt only for specific objects described here! |
             && |For program reports - \{READ TADIR: REPS object_name\}. |
             && |If asked to find only a class: \{READ: CLASS = class_name\}. |
             && |If asked to find a method: \{READ METH class_name=>method_name\}. |
             && cl_abap_char_utilities=>newline
             && cl_abap_char_utilities=>newline
             && |If they ask for a code review, use "Code_review -object name" |
             && cl_abap_char_utilities=>newline
             && |If you need to show the code, add the object type to the response - \{SHOW - objname\}. |
             && |Don't lose the READ command! |
             && cl_abap_char_utilities=>newline
             && |Allowed substitutions here only PROG, REPS, CLAS, METH!!! |
             && cl_abap_char_utilities=>newline
             && cl_abap_char_utilities=>newline
             && |There can be multiple commands - don't lose the READ commands! |
             && cl_abap_char_utilities=>newline
             && cl_abap_char_utilities=>newline
             && |A class and a method are a composite object - you can connect them using =>|
             && cl_abap_char_utilities=>newline
             && |A method without a class is "Undescribed." Don't invent a class yourself!!! |
             && |No class means "Undescribed." Take the original prompt! |
             && |Replace the text of the original prompt and replace the recognized parts with commands! |
             && cl_abap_char_utilities=>newline
             && cl_abap_char_utilities=>newline
             && |Prompts parts don't translate! Let it be original language!|
             && cl_abap_char_utilities=>newline
             && |For example, for "Compare programs z_1 z_2 z_test. Rating the programs," return |
             && |"Compare programs \{READ TADIR: REPS z_1\} \{READ TADIR: REPS z_2\} |
             && |\{READ TADIR: REPS z_test\}. Rating all programs Code_review - z_1, z_2, z_test".|
             && cl_abap_char_utilities=>newline
             && cl_abap_char_utilities=>newline
             && |PROMPT:|.
  ENDMETHOD.

  METHOD get_data_agent_prompt.
    rv_prompt = |You are a Senior ABAP Data Search Agent. Search for data in SAP tables and objects. |
             && |Use table commands to query data from TADIR, TFDIR, and other system tables. |
             && |Return brief, relevant information without unnecessary details.|.
  ENDMETHOD.

  METHOD get_code_review_prompt.
    rv_prompt = |You are a Senior ABAP Code Review Agent. Review only the provided ABAP code. |
             && |Do not make an abstract review. Find concrete issues, risks, and improvement suggestions. |
             && |Return readable Markdown with real line breaks: put every heading, list item, paragraph, |
             && |and fenced code block on separate lines.|.
  ENDMETHOD.

  METHOD get_create_object_prompt.
    rv_prompt = |You are a Senior ABAP Create Object Agent. Prepare the final instruction for creating or changing |
             && |an ABAP object. Keep the original language of the user request. If code context is needed, keep |
             && |the AGENT:CODE_SEARCH dependency visible so it can be resolved before the final answer. |
             && |Do not delete objects and do not perform destructive actions.|.
  ENDMETHOD.

  METHOD get_code_reader_prompt.
    rv_prompt = |You are a Senior ABAP Code Reader Agent. Find all READ commands in the input text and resolve them. |
             && |For \{ READ TADIR: REPS object_name \} or PROG, read the ABAP report source. |
             && |For \{ READ: CLASS = class_name \}, read class sections and method includes. |
             && |For \{ READ METH class_name=>method_name \}, read only the requested method include. |
             && |Return resolved source code with object names. Do not call LLM and do not invent missing objects.|.
  ENDMETHOD.

  METHOD get_prompt_by_agent.
    CASE i_agent.
      WHEN c_agent_orchestrator.
        rv_prompt = get_orchestrator_prompt( ).
      WHEN c_agent_code_search.
        rv_prompt = get_code_agent_prompt( ).
      WHEN c_agent_code_review.
        rv_prompt = get_code_review_prompt( ).
      WHEN c_agent_data_search.
        rv_prompt = get_data_agent_prompt( ).
      WHEN c_agent_create_obj.
        rv_prompt = get_create_object_prompt( ).
      WHEN c_agent_code_reader.
        rv_prompt = get_code_reader_prompt( ).
      WHEN OTHERS.
        rv_prompt = |Agent '{ i_agent }' not found|.
    ENDCASE.
  ENDMETHOD.

ENDCLASS.
