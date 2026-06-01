CLASS zcl_ai_messages DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    TYPES:
      BEGIN OF ty_message,
        session_id  TYPE i,
        message_id  TYPE i,
        role        TYPE string,
        agent       TYPE string,
        prompt_type TYPE string,
        duration_seconds TYPE string,
        content     TYPE string,
      END OF ty_message,
      tt_messages TYPE STANDARD TABLE OF ty_message WITH NON-UNIQUE DEFAULT KEY,

      BEGIN OF ty_agent_request,
        agent           TYPE string,
        object_type     TYPE string,
        object_name     TYPE string,
        relevant_prompt TYPE string,
        raw_command      TYPE string,
      END OF ty_agent_request,
      tt_agent_requests TYPE STANDARD TABLE OF ty_agent_request WITH NON-UNIQUE DEFAULT KEY,
      tt_strings        TYPE STANDARD TABLE OF string WITH NON-UNIQUE DEFAULT KEY,
      tt_source         TYPE STANDARD TABLE OF string WITH NON-UNIQUE DEFAULT KEY.

    METHODS constructor
      IMPORTING i_user_prompt TYPE string
                io_prompts    TYPE REF TO zcl_ai_agents_prompts
                i_session_id  TYPE i OPTIONAL.

    METHODS build_orchestrator_request
      RETURNING VALUE(rv_prompt) TYPE string.

    METHODS add_message
      IMPORTING i_role    TYPE string
                i_agent   TYPE string OPTIONAL
                i_prompt_type TYPE string OPTIONAL
                i_duration_seconds TYPE string OPTIONAL
                i_content TYPE string.

    METHODS parse_agent_requests
      IMPORTING i_orchestrator_answer TYPE string
      RETURNING VALUE(rt_requests)    TYPE tt_agent_requests.

    METHODS build_agent_request
      IMPORTING is_request       TYPE ty_agent_request
      RETURNING VALUE(rv_prompt) TYPE string.

    METHODS build_agent_requests
      IMPORTING it_requests      TYPE tt_agent_requests
      RETURNING VALUE(rv_prompt) TYPE string.

    METHODS build_read_command
      IMPORTING is_request       TYPE ty_agent_request
      RETURNING VALUE(rv_command) TYPE string.

    METHODS enrich_agent_answer
      IMPORTING i_agent_answer   TYPE string
      RETURNING VALUE(rv_answer) TYPE string.

    METHODS build_final_request
      IMPORTING i_user_prompt    TYPE string OPTIONAL
      RETURNING VALUE(rv_prompt) TYPE string.

    METHODS get_resolved_code
      RETURNING VALUE(rv_code) TYPE string.

    METHODS get_agent_error
      RETURNING VALUE(rv_error) TYPE string.

    METHODS needs_code_context
      RETURNING VALUE(rv_needed) TYPE abap_bool.

    METHODS has_text_after_agent_commands
      IMPORTING i_orchestrator_answer TYPE string
      RETURNING VALUE(rv_has_text)    TYPE abap_bool.

    METHODS get_messages
      RETURNING VALUE(rt_messages) TYPE tt_messages.

protected section.
  PRIVATE SECTION.
    DATA mv_user_prompt TYPE string.
    DATA mv_session_id  TYPE i.
    DATA mt_messages    TYPE tt_messages.
    DATA mo_prompts     TYPE REF TO zcl_ai_agents_prompts.

ENDCLASS.



CLASS ZCL_AI_MESSAGES IMPLEMENTATION.


  METHOD constructor.
    mv_user_prompt = i_user_prompt.
    mv_session_id = i_session_id.
    mo_prompts = io_prompts.
    IF mv_session_id IS INITIAL.
      mv_session_id = 1.
    ENDIF.

    add_message(
      i_role        = 'user'
      i_agent       = 'USER'
      i_prompt_type = 'USER_PROMPT'
      i_content     = mv_user_prompt ).
  ENDMETHOD.


  METHOD build_orchestrator_request.
    rv_prompt = mo_prompts->get_orchestrator_prompt( )
             && cl_abap_char_utilities=>newline
             && cl_abap_char_utilities=>newline
             && |PROMPT: { mv_user_prompt }|.

    add_message(
      i_role        = 'user'
      i_agent       = zcl_ai_agents_prompts=>c_agent_orchestrator
      i_prompt_type = 'SYSTEM_PROMPT'
      i_content     = rv_prompt ).
  ENDMETHOD.


  METHOD add_message.
    APPEND VALUE #(
      session_id  = mv_session_id
      message_id  = lines( mt_messages ) + 1
      role        = i_role
      agent       = i_agent
      prompt_type = i_prompt_type
      duration_seconds = i_duration_seconds
      content     = i_content ) TO mt_messages.
  ENDMETHOD.


  METHOD parse_agent_requests.
    DATA lv_rest TYPE string.
    DATA lv_pos  TYPE i.
    DATA lv_end  TYPE i.
    DATA lt_seen_commands TYPE tt_strings.

    lv_rest = i_orchestrator_answer.
    REPLACE ALL OCCURRENCES OF REGEX '\{\s*AGENT\s*:' IN lv_rest WITH '{AGENT:'.

    WHILE lv_rest CS '{AGENT:'.
      FIND FIRST OCCURRENCE OF '{AGENT:' IN lv_rest MATCH OFFSET lv_pos.
      lv_rest = substring( val = lv_rest off = lv_pos + 7 ).

      FIND FIRST OCCURRENCE OF '}' IN lv_rest MATCH OFFSET lv_end.
      IF sy-subrc <> 0.
        EXIT.
      ENDIF.

      DATA(lv_command) = substring( val = lv_rest len = lv_end ).
      lv_rest = substring( val = lv_rest off = lv_end + 1 ).

      DATA(lv_seen_command) = lv_command.
      TRANSLATE lv_seen_command TO UPPER CASE.
      CONDENSE lv_seen_command.

      READ TABLE lt_seen_commands WITH KEY table_line = lv_seen_command TRANSPORTING NO FIELDS.
      IF sy-subrc = 0.
        CONTINUE.
      ENDIF.
      APPEND lv_seen_command TO lt_seen_commands.

      DATA lt_parts TYPE STANDARD TABLE OF string WITH NON-UNIQUE DEFAULT KEY.
      SPLIT lv_command AT space INTO TABLE lt_parts.
      DELETE lt_parts WHERE table_line IS INITIAL.
      IF lt_parts IS INITIAL.
        CONTINUE.
      ENDIF.

      DATA(ls_request) = VALUE ty_agent_request(
        agent      = lt_parts[ 1 ]
        raw_command = |{ '{' }AGENT:{ lv_command }{ '}' }| ).
      DATA lv_part TYPE string.
      DATA lv_part_upper TYPE string.
      DATA lv_arrow TYPE i.
      DATA lv_class_name TYPE string.
      DATA lv_method_name TYPE string.

      TRANSLATE ls_request-agent TO UPPER CASE.

      IF ls_request-agent = zcl_ai_agents_prompts=>c_agent_code_search
      OR ls_request-agent = zcl_ai_agents_prompts=>c_agent_code_change
      OR ls_request-agent = zcl_ai_agents_prompts=>c_agent_code_review
      OR ls_request-agent = zcl_ai_agents_prompts=>c_agent_code_diff
      OR ls_request-agent = zcl_ai_agents_prompts=>c_agent_create_obj
      OR ls_request-agent = zcl_ai_agents_prompts=>c_agent_save.
        LOOP AT lt_parts INTO lv_part FROM 2.
          lv_part_upper = lv_part.
          TRANSLATE lv_part_upper TO UPPER CASE.

          IF lv_part_upper CP 'CLASS_NAME=>*'.
            FIND FIRST OCCURRENCE OF '=>' IN lv_part MATCH OFFSET lv_arrow.
            IF sy-subrc = 0.
              lv_class_name = substring( val = lv_part off = lv_arrow + 2 ).
            ENDIF.
          ELSEIF lv_part_upper CP 'METHOD_NAME=>*'.
            FIND FIRST OCCURRENCE OF '=>' IN lv_part MATCH OFFSET lv_arrow.
            IF sy-subrc = 0.
              lv_method_name = substring( val = lv_part off = lv_arrow + 2 ).
            ENDIF.
          ENDIF.
        ENDLOOP.

        IF lv_class_name IS NOT INITIAL AND lv_method_name IS NOT INITIAL.
          ls_request-object_type = 'METH'.
          ls_request-object_name = |{ lv_class_name }=>{ lv_method_name }|.

          LOOP AT lt_parts INTO lv_part FROM 2.
            lv_part_upper = lv_part.
            TRANSLATE lv_part_upper TO UPPER CASE.
            CHECK lv_part_upper NP 'CLASS_NAME=>*'
              AND lv_part_upper NP 'METHOD_NAME=>*'.

            IF ls_request-relevant_prompt IS NOT INITIAL.
              ls_request-relevant_prompt = ls_request-relevant_prompt && space.
            ENDIF.
            ls_request-relevant_prompt = ls_request-relevant_prompt && lv_part.
          ENDLOOP.
        ELSEIF lines( lt_parts ) >= 2.
          ls_request-object_type = lt_parts[ 2 ].
          TRANSLATE ls_request-object_type TO UPPER CASE.
          IF lines( lt_parts ) >= 3.
            ls_request-object_name = lt_parts[ 3 ].
          ENDIF.
          IF lines( lt_parts ) >= 4.
            LOOP AT lt_parts INTO lv_part FROM 4.
              IF ls_request-relevant_prompt IS NOT INITIAL.
                ls_request-relevant_prompt = ls_request-relevant_prompt && space.
              ENDIF.
              ls_request-relevant_prompt = ls_request-relevant_prompt && lv_part.
            ENDLOOP.
          ENDIF.
        ENDIF.
      ELSE.
        LOOP AT lt_parts INTO lv_part FROM 2.
          IF ls_request-relevant_prompt IS NOT INITIAL.
            ls_request-relevant_prompt = ls_request-relevant_prompt && space.
          ENDIF.
          ls_request-relevant_prompt = ls_request-relevant_prompt && lv_part.
        ENDLOOP.
      ENDIF.

      IF ls_request-relevant_prompt IS NOT INITIAL.
        IF ls_request-object_type IS NOT INITIAL
        AND ls_request-object_name IS NOT INITIAL.
          DATA(lv_raw_relevant_prompt) = ls_request-raw_command.
          REPLACE FIRST OCCURRENCE OF REGEX '^\{\s*AGENT\s*:\s*\S+\s+\S+\s+\S+\s*'
            IN lv_raw_relevant_prompt WITH ''.
          REPLACE FIRST OCCURRENCE OF REGEX '\}\s*$'
            IN lv_raw_relevant_prompt WITH ''.
          REPLACE FIRST OCCURRENCE OF REGEX '^\s+' IN lv_raw_relevant_prompt WITH ''.
          REPLACE FIRST OCCURRENCE OF REGEX '^\+\s*' IN lv_raw_relevant_prompt WITH ''.
          REPLACE FIRST OCCURRENCE OF REGEX '\s+$' IN lv_raw_relevant_prompt WITH ''.
          IF lv_raw_relevant_prompt IS NOT INITIAL.
            ls_request-relevant_prompt = lv_raw_relevant_prompt.
          ENDIF.
        ENDIF.
      ENDIF.

      APPEND ls_request TO rt_requests.
    ENDWHILE.
  ENDMETHOD.


  METHOD build_agent_request.
    rv_prompt = mo_prompts->get_prompt_by_agent( is_request-agent )
             && cl_abap_char_utilities=>newline
             && cl_abap_char_utilities=>newline
             && |ORIGINAL PROMPT: { mv_user_prompt }|
             && cl_abap_char_utilities=>newline
             && |AGENT COMMAND: { is_request-raw_command }|.

    IF is_request-object_type IS NOT INITIAL OR is_request-object_name IS NOT INITIAL.
      rv_prompt = rv_prompt
               && cl_abap_char_utilities=>newline
               && |OBJECT: { is_request-object_type } { is_request-object_name }|.
    ENDIF.

    IF is_request-relevant_prompt IS NOT INITIAL.
      rv_prompt = rv_prompt
               && cl_abap_char_utilities=>newline
               && |RELEVANT PROMPT PART: { is_request-relevant_prompt }|.
    ENDIF.

    IF is_request-agent = zcl_ai_agents_prompts=>c_agent_code_review.
      rv_prompt = rv_prompt
               && cl_abap_char_utilities=>newline
               && cl_abap_char_utilities=>newline
               && |CODE CONTEXT:|
               && cl_abap_char_utilities=>newline
               && COND string(
                    WHEN get_resolved_code( ) IS NOT INITIAL THEN get_resolved_code( )
                    ELSE 'No code context was resolved.' ).
    ENDIF.

    add_message(
      i_role        = 'user'
      i_agent       = is_request-agent
      i_prompt_type = 'AGENT_PROMPT'
      i_content     = rv_prompt ).
  ENDMETHOD.


  METHOD build_agent_requests.
    READ TABLE it_requests INDEX 1 INTO DATA(ls_first_request).
    CHECK sy-subrc = 0.

    rv_prompt = mo_prompts->get_prompt_by_agent( ls_first_request-agent )
             && cl_abap_char_utilities=>newline
             && cl_abap_char_utilities=>newline
             && |ORIGINAL PROMPT: { mv_user_prompt }|
             && cl_abap_char_utilities=>newline
             && |AGENT COMMANDS:|.

    LOOP AT it_requests INTO DATA(ls_request).
      rv_prompt = rv_prompt
               && cl_abap_char_utilities=>newline
               && ls_request-raw_command.

      IF ls_request-object_type IS NOT INITIAL OR ls_request-object_name IS NOT INITIAL.
        rv_prompt = rv_prompt
                 && cl_abap_char_utilities=>newline
                 && |OBJECT: { ls_request-object_type } { ls_request-object_name }|.
      ENDIF.

      IF ls_request-relevant_prompt IS NOT INITIAL.
        rv_prompt = rv_prompt
                 && cl_abap_char_utilities=>newline
                 && |RELEVANT PROMPT PART: { ls_request-relevant_prompt }|.
      ENDIF.
    ENDLOOP.

    IF ls_first_request-agent = zcl_ai_agents_prompts=>c_agent_code_review.
      rv_prompt = rv_prompt
               && cl_abap_char_utilities=>newline
               && cl_abap_char_utilities=>newline
               && |CODE CONTEXT:|
               && cl_abap_char_utilities=>newline
               && COND string(
                    WHEN get_resolved_code( ) IS NOT INITIAL THEN get_resolved_code( )
                    ELSE 'No code context was resolved.' ).
    ENDIF.

    add_message(
      i_role        = 'user'
      i_agent       = ls_first_request-agent
      i_prompt_type = 'AGENT_PROMPT'
      i_content     = rv_prompt ).
  ENDMETHOD.


  METHOD build_read_command.
    CHECK is_request-agent = zcl_ai_agents_prompts=>c_agent_code_search
       OR is_request-agent = zcl_ai_agents_prompts=>c_agent_code_change
       OR is_request-agent = zcl_ai_agents_prompts=>c_agent_code_review
       OR is_request-agent = zcl_ai_agents_prompts=>c_agent_code_diff
       OR is_request-agent = zcl_ai_agents_prompts=>c_agent_create_obj
       OR is_request-agent = zcl_ai_agents_prompts=>c_agent_save.
    CHECK is_request-object_name IS NOT INITIAL.

    CASE is_request-object_type.
      WHEN 'REPS' OR 'PROG' OR 'PROGRAM' OR 'REPORT'.
        rv_command = |{ '{' }READ TADIR: REPS { is_request-object_name }{ '}' }|.
      WHEN 'CLAS' OR 'CLASS'.
        rv_command = |{ '{' }READ: CLASS = { is_request-object_name }{ '}' }|.
      WHEN 'METH' OR 'METHOD'.
        rv_command = |{ '{' }READ METH { is_request-object_name }{ '}' }|.
    ENDCASE.
  ENDMETHOD.


  METHOD enrich_agent_answer.
    rv_answer = i_agent_answer.

    DATA(lv_context) = zcl_ai_code_reader=>resolve_read_commands( i_agent_answer ).
    IF lv_context IS NOT INITIAL.
      rv_answer = rv_answer
               && cl_abap_char_utilities=>newline
               && lv_context.
    ENDIF.
  ENDMETHOD.


  METHOD build_final_request.
    DATA(lv_user_prompt) = COND string(
      WHEN i_user_prompt IS NOT INITIAL THEN i_user_prompt
      ELSE mv_user_prompt ).

    rv_prompt = |You are a Senior ABAP. Return readable Markdown with real line breaks: |
             && |put every heading, list item, paragraph, and fenced code block on separate lines. |.

    rv_prompt = rv_prompt
             && |For code change requests, return the complete changed ABAP source in an abap fenced code block. with remark CHANGES:YES at the end |
             && |For create object requests, return the complete new ABAP source in an abap fenced code block.  with remark CHANGES:YES at the end |
             && |For code change requests only: if you only provide recommendations and did not change the code, put CHANGES:NO at the very end of the answer. |
             && |For create object requests, do not use CHANGES:NO; return the proposed new object source code. |.

    rv_prompt = rv_prompt
             && cl_abap_char_utilities=>newline
             && cl_abap_char_utilities=>newline
             && |USER PROMPT:|
             && cl_abap_char_utilities=>newline
             && lv_user_prompt
             && cl_abap_char_utilities=>newline
             && cl_abap_char_utilities=>newline
             && COND string(
                  WHEN get_resolved_code( ) IS NOT INITIAL THEN get_resolved_code( )
                  WHEN needs_code_context( ) = abap_true THEN 'No code context was resolved.'
                  ELSE '' ).

    add_message(
      i_role        = 'user'
      i_agent       = 'FINAL'
      i_prompt_type = 'AGENT_PROMPT'
      i_content     = rv_prompt ).
  ENDMETHOD.


  METHOD get_resolved_code.
    DATA lt_seen TYPE tt_strings.

    LOOP AT mt_messages INTO DATA(ls_message).
      CHECK ls_message-agent = zcl_ai_agents_prompts=>c_agent_code_reader.
      CHECK ls_message-role = 'assistant'.

      IF rv_code IS NOT INITIAL.
        rv_code = rv_code
               && cl_abap_char_utilities=>newline
               && cl_abap_char_utilities=>newline.
      ENDIF.

      DATA(lv_clean_code) = ls_message-content.
      REPLACE ALL OCCURRENCES OF REGEX 'Resolved \{READ[^\n\r]*\}:\s*' IN lv_clean_code WITH ''.
      REPLACE ALL OCCURRENCES OF REGEX 'Source for program [^:\n\r]*:\s*' IN lv_clean_code WITH ''.
      REPLACE ALL OCCURRENCES OF REGEX 'Source for class [^:\n\r]*:\s*' IN lv_clean_code WITH ''.
      REPLACE ALL OCCURRENCES OF REGEX 'Source for method [^:\n\r]*:\s*' IN lv_clean_code WITH ''.

      DATA(lv_seen_key) = lv_clean_code.
      CONDENSE lv_seen_key.

      READ TABLE lt_seen WITH KEY table_line = lv_seen_key TRANSPORTING NO FIELDS.
      IF sy-subrc = 0.
        CONTINUE.
      ENDIF.
      APPEND lv_seen_key TO lt_seen.

      rv_code = rv_code && lv_clean_code.
    ENDLOOP.
  ENDMETHOD.


  METHOD get_agent_error.
    LOOP AT mt_messages INTO DATA(ls_message).
      CHECK ls_message-agent = zcl_ai_agents_prompts=>c_agent_code_reader.
      CHECK ls_message-role = 'assistant'.

      DATA(lv_content_upper) = ls_message-content.
      TRANSLATE lv_content_upper TO UPPER CASE.
      CONDENSE lv_content_upper.

      IF lv_content_upper CP 'SOURCE FOR PROGRAM * WAS NOT FOUND*'
      OR lv_content_upper CP 'SOURCE FOR PROGRAM * CANNOT BE READ*'
      OR lv_content_upper CP 'RESOLVED {READ*: SOURCE FOR PROGRAM * WAS NOT FOUND*'
      OR lv_content_upper CP 'RESOLVED {READ*: SOURCE FOR PROGRAM * CANNOT BE READ*'
      OR lv_content_upper CP 'CLASS * WAS NOT FOUND*'
      OR lv_content_upper CP 'METHOD * WAS NOT FOUND*'
      OR lv_content_upper CP 'METHOD COMMAND IS INCOMPLETE*'
      OR lv_content_upper CP 'NO CODE CONTEXT WAS RESOLVED*'.
        rv_error = ls_message-content.
        RETURN.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.


  METHOD needs_code_context.
    DATA lv_has_code_search TYPE abap_bool.
    DATA lv_has_code_review TYPE abap_bool.

    LOOP AT mt_messages INTO DATA(ls_message).
      DATA(lv_content_upper) = ls_message-content.
      TRANSLATE lv_content_upper TO UPPER CASE.

      IF ls_message-agent = zcl_ai_agents_prompts=>c_agent_code_search
      OR ls_message-agent = zcl_ai_agents_prompts=>c_agent_code_reader
      OR lv_content_upper CS 'CODE_SEARCH'.
        lv_has_code_search = abap_true.
      ENDIF.

      IF ls_message-agent = zcl_ai_agents_prompts=>c_agent_code_review.
        lv_has_code_review = abap_true.
      ENDIF.
    ENDLOOP.

    rv_needed = xsdbool( lv_has_code_search = abap_true AND lv_has_code_review = abap_true ).
  ENDMETHOD.


  METHOD has_text_after_agent_commands.
    DATA(lv_text) = i_orchestrator_answer.

    REPLACE ALL OCCURRENCES OF REGEX '\{\s*AGENT\s*:[^}]*\}' IN lv_text WITH ''.
    REPLACE ALL OCCURRENCES OF REGEX '\{\s*READ[^}]*\}' IN lv_text WITH ''.
    REPLACE ALL OCCURRENCES OF REGEX '\{\s*SHOW[^}]*\}' IN lv_text WITH ''.
    REPLACE ALL OCCURRENCES OF REGEX '---[\s\r\n]*Tokens:.*$' IN lv_text WITH ''.
    REPLACE ALL OCCURRENCES OF REGEX 'Tokens:.*$' IN lv_text WITH ''.
    REPLACE ALL OCCURRENCES OF REGEX '^[\s\r\n-]+$' IN lv_text WITH ''.
    REPLACE ALL OCCURRENCES OF REGEX '---' IN lv_text WITH ''.
    CONDENSE lv_text.

    rv_has_text = xsdbool( lv_text IS NOT INITIAL ).
  ENDMETHOD.


  METHOD get_messages.
    rt_messages = mt_messages.
  ENDMETHOD.
ENDCLASS.
