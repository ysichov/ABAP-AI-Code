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

    METHODS get_total_token_usage
      IMPORTING i_extra_text TYPE string OPTIONAL
      RETURNING VALUE(rv_usage) TYPE string.

    METHODS needs_code_context
      RETURNING VALUE(rv_needed) TYPE abap_bool.

    METHODS has_text_after_agent_commands
      IMPORTING i_orchestrator_answer TYPE string
      RETURNING VALUE(rv_has_text)    TYPE abap_bool.

    CLASS-METHODS strip_log_info
      IMPORTING i_text        TYPE string
      RETURNING VALUE(rv_text) TYPE string.

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
             && mv_user_prompt.

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


  METHOD get_total_token_usage.

    DATA lv_prompt_tokens TYPE i.
    DATA lv_completion_tokens TYPE i.
    DATA lv_total_tokens TYPE i.
    DATA lv_cached_tokens TYPE i.
    DATA lv_prompt_text TYPE string.
    DATA lv_completion_text TYPE string.
    DATA lv_total_text TYPE string.
    DATA lv_cached_text TYPE string.

    LOOP AT mt_messages INTO DATA(ls_message).
      CLEAR: lv_prompt_text,
             lv_completion_text,
             lv_total_text,
             lv_cached_text.

      FIND FIRST OCCURRENCE OF REGEX 'prompt=([0-9]+)'
        IN ls_message-content SUBMATCHES lv_prompt_text.
      IF lv_prompt_text IS INITIAL.
        FIND FIRST OCCURRENCE OF REGEX 'input=([0-9]+)'
          IN ls_message-content SUBMATCHES lv_prompt_text.
      ENDIF.

      FIND FIRST OCCURRENCE OF REGEX 'completion=([0-9]+)'
        IN ls_message-content SUBMATCHES lv_completion_text.
      IF lv_completion_text IS INITIAL.
        FIND FIRST OCCURRENCE OF REGEX 'output=([0-9]+)'
          IN ls_message-content SUBMATCHES lv_completion_text.
      ENDIF.

      FIND FIRST OCCURRENCE OF REGEX 'total=([0-9]+)'
        IN ls_message-content SUBMATCHES lv_total_text.

      FIND FIRST OCCURRENCE OF REGEX 'cached=([0-9]+)'
        IN ls_message-content SUBMATCHES lv_cached_text.

      IF lv_prompt_text IS NOT INITIAL.
        lv_prompt_tokens = lv_prompt_tokens + lv_prompt_text.
      ENDIF.
      IF lv_completion_text IS NOT INITIAL.
        lv_completion_tokens = lv_completion_tokens + lv_completion_text.
      ENDIF.
      IF lv_total_text IS NOT INITIAL.
        lv_total_tokens = lv_total_tokens + lv_total_text.
      ENDIF.
      IF lv_cached_text IS NOT INITIAL.
        lv_cached_tokens = lv_cached_tokens + lv_cached_text.
      ENDIF.
    ENDLOOP.

    IF i_extra_text IS NOT INITIAL.
      CLEAR: lv_prompt_text,
             lv_completion_text,
             lv_total_text,
             lv_cached_text.

      FIND FIRST OCCURRENCE OF REGEX 'prompt=([0-9]+)'
        IN i_extra_text SUBMATCHES lv_prompt_text.
      IF lv_prompt_text IS INITIAL.
        FIND FIRST OCCURRENCE OF REGEX 'input=([0-9]+)'
          IN i_extra_text SUBMATCHES lv_prompt_text.
      ENDIF.

      FIND FIRST OCCURRENCE OF REGEX 'completion=([0-9]+)'
        IN i_extra_text SUBMATCHES lv_completion_text.
      IF lv_completion_text IS INITIAL.
        FIND FIRST OCCURRENCE OF REGEX 'output=([0-9]+)'
          IN i_extra_text SUBMATCHES lv_completion_text.
      ENDIF.

      FIND FIRST OCCURRENCE OF REGEX 'total=([0-9]+)'
        IN i_extra_text SUBMATCHES lv_total_text.

      FIND FIRST OCCURRENCE OF REGEX 'cached=([0-9]+)'
        IN i_extra_text SUBMATCHES lv_cached_text.

      IF lv_prompt_text IS NOT INITIAL.
        lv_prompt_tokens = lv_prompt_tokens + lv_prompt_text.
      ENDIF.
      IF lv_completion_text IS NOT INITIAL.
        lv_completion_tokens = lv_completion_tokens + lv_completion_text.
      ENDIF.
      IF lv_total_text IS NOT INITIAL.
        lv_total_tokens = lv_total_tokens + lv_total_text.
      ENDIF.
      IF lv_cached_text IS NOT INITIAL.
        lv_cached_tokens = lv_cached_tokens + lv_cached_text.
      ENDIF.
    ENDIF.

    IF lv_total_tokens IS NOT INITIAL.
      rv_usage = |Total tokens: input={ lv_prompt_tokens } output={ lv_completion_tokens } total={ lv_total_tokens } cached={ lv_cached_tokens }|.
    ENDIF.

  ENDMETHOD.


  METHOD parse_agent_requests.
    DATA lv_rest TYPE string.
    DATA lv_pos  TYPE i.
    DATA lv_end  TYPE i.
    DATA lt_seen_commands TYPE tt_strings.

    lv_rest = i_orchestrator_answer.
    REPLACE ALL OCCURRENCES OF REGEX '\{\s*AGENT\s*:' IN lv_rest WITH '{AGENT:'.

    DATA lv_prefix TYPE string.
    WHILE lv_rest CS '{AGENT:'.
      FIND FIRST OCCURRENCE OF '{AGENT:' IN lv_rest MATCH OFFSET lv_pos.
      lv_prefix = substring( val = lv_rest len = lv_pos ).
      REPLACE ALL OCCURRENCES OF REGEX '^\s+|\s+$' IN lv_prefix WITH ''.
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
          DATA(lv_part2) = lt_parts[ 2 ].
          DATA(lv_part2_upper) = lv_part2.
          TRANSLATE lv_part2_upper TO UPPER CASE.
          " {AGENT:CODE_SEARCH CLASS=>METHOD ...} - part2 contains '=>'
          IF lv_part2 CS '=>'.
            ls_request-object_type = 'METH'.
            ls_request-object_name = lv_part2_upper.
            IF lines( lt_parts ) >= 3.
              LOOP AT lt_parts INTO lv_part FROM 3.
                IF ls_request-relevant_prompt IS NOT INITIAL.
                  ls_request-relevant_prompt = ls_request-relevant_prompt && space.
                ENDIF.
                ls_request-relevant_prompt = ls_request-relevant_prompt && lv_part.
              ENDLOOP.
            ENDIF.
          ELSE.
            ls_request-object_type = lv_part2_upper.
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

      IF lv_prefix IS NOT INITIAL.
        IF ls_request-relevant_prompt IS NOT INITIAL.
          ls_request-relevant_prompt = lv_prefix && space && ls_request-relevant_prompt.
        ELSE.
          ls_request-relevant_prompt = lv_prefix.
        ENDIF.
      ENDIF.

      APPEND ls_request TO rt_requests.
    ENDWHILE.

    " Text remaining after last tag -> append to last request's relevant_prompt
    IF rt_requests IS NOT INITIAL AND lv_rest IS NOT INITIAL.
      DATA(lv_tail) = lv_rest.
      REPLACE ALL OCCURRENCES OF REGEX '^\s+' IN lv_tail WITH ''.
      REPLACE ALL OCCURRENCES OF REGEX '\s+$' IN lv_tail WITH ''.
      IF lv_tail IS NOT INITIAL.
        DATA(lv_last_idx) = lines( rt_requests ).
        FIELD-SYMBOLS <ls_last> TYPE ty_agent_request.
        READ TABLE rt_requests ASSIGNING <ls_last> INDEX lv_last_idx.
        IF sy-subrc = 0.
          IF <ls_last>-relevant_prompt IS NOT INITIAL.
            <ls_last>-relevant_prompt = <ls_last>-relevant_prompt && cl_abap_char_utilities=>newline.
          ENDIF.
          <ls_last>-relevant_prompt = <ls_last>-relevant_prompt && lv_tail.
        ENDIF.
      ENDIF.
    ENDIF.
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
        rv_command = |{ '{' }READ TADIR: PROG { is_request-object_name }{ '}' }|.
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

    rv_prompt = mo_prompts->get_final_prompt( ).

    rv_prompt = rv_prompt
             && cl_abap_char_utilities=>newline
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
      OR ls_message-agent = zcl_ai_agents_prompts=>c_agent_code_reader.
        lv_has_code_search = abap_true.
      ENDIF.

      IF ls_message-role = 'assistant'
      AND ls_message-agent = zcl_ai_agents_prompts=>c_agent_orchestrator
      AND lv_content_upper CS '{AGENT:CODE_SEARCH'.
        lv_has_code_search = abap_true.
      ENDIF.

      IF ls_message-agent = zcl_ai_agents_prompts=>c_agent_code_review.
        lv_has_code_review = abap_true.
      ENDIF.
    ENDLOOP.

    rv_needed = xsdbool( lv_has_code_search = abap_true AND lv_has_code_review = abap_true ).
  ENDMETHOD.


  METHOD has_text_after_agent_commands.
    DATA(lv_text) = strip_log_info( i_orchestrator_answer ).

    REPLACE ALL OCCURRENCES OF REGEX '\{\s*AGENT\s*:[^}]*\}' IN lv_text WITH ''.
    REPLACE ALL OCCURRENCES OF REGEX '\{\s*READ[^}]*\}' IN lv_text WITH ''.
    REPLACE ALL OCCURRENCES OF REGEX '\{\s*SHOW[^}]*\}' IN lv_text WITH ''.
    REPLACE ALL OCCURRENCES OF REGEX '^[\s\r\n-]+$' IN lv_text WITH ''.
    REPLACE ALL OCCURRENCES OF REGEX '---' IN lv_text WITH ''.
    CONDENSE lv_text.

    rv_has_text = xsdbool( lv_text IS NOT INITIAL ).
  ENDMETHOD.


  METHOD strip_log_info.
    rv_text = i_text.
    REPLACE ALL OCCURRENCES OF REGEX '[\r\n]+---[\s\r\n]*Tokens:.*$' IN rv_text WITH ''.
    REPLACE ALL OCCURRENCES OF REGEX '[\r\n]+Tokens:.*$' IN rv_text WITH ''.
    REPLACE ALL OCCURRENCES OF REGEX '^\s+' IN rv_text WITH ''.
    REPLACE ALL OCCURRENCES OF REGEX '\s+$' IN rv_text WITH ''.
  ENDMETHOD.


  METHOD get_messages.
    rt_messages = mt_messages.
  ENDMETHOD.
ENDCLASS.
