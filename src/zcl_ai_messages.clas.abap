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
      tt_source         TYPE STANDARD TABLE OF string WITH NON-UNIQUE DEFAULT KEY.

    METHODS constructor
      IMPORTING i_user_prompt TYPE string
                i_session_id  TYPE i OPTIONAL.

    METHODS build_orchestrator_request
      RETURNING VALUE(rv_prompt) TYPE string.

    METHODS add_message
      IMPORTING i_role    TYPE string
                i_agent   TYPE string OPTIONAL
                i_prompt_type TYPE string OPTIONAL
                i_content TYPE string.

    METHODS parse_agent_requests
      IMPORTING i_orchestrator_answer TYPE string
      RETURNING VALUE(rt_requests)    TYPE tt_agent_requests.

    METHODS build_agent_request
      IMPORTING is_request       TYPE ty_agent_request
      RETURNING VALUE(rv_prompt) TYPE string.

    METHODS build_read_command
      IMPORTING is_request       TYPE ty_agent_request
      RETURNING VALUE(rv_command) TYPE string.

    METHODS enrich_agent_answer
      IMPORTING i_agent_answer   TYPE string
      RETURNING VALUE(rv_answer) TYPE string.

    METHODS build_final_request
      RETURNING VALUE(rv_prompt) TYPE string.

    METHODS get_messages
      RETURNING VALUE(rt_messages) TYPE tt_messages.

  PRIVATE SECTION.
    DATA mv_user_prompt TYPE string.
    DATA mv_session_id  TYPE i.
    DATA mt_messages    TYPE tt_messages.

ENDCLASS.

CLASS zcl_ai_messages IMPLEMENTATION.

  METHOD constructor.
    mv_user_prompt = i_user_prompt.
    mv_session_id = i_session_id.
    IF mv_session_id IS INITIAL.
      mv_session_id = 1.
    ENDIF.
  ENDMETHOD.

  METHOD build_orchestrator_request.
    rv_prompt = zcl_ai_agents_prompts=>get_orchestrator_prompt( )
             && cl_abap_char_utilities=>newline
             && cl_abap_char_utilities=>newline
             && |PROMPT: { mv_user_prompt }|.

    add_message(
      i_role        = 'user'
      i_agent       = zcl_ai_agents_prompts=>c_agent_orchestrator
      i_prompt_type = 'USER_PROMPT'
      i_content     = rv_prompt ).
  ENDMETHOD.

  METHOD add_message.
    APPEND VALUE #(
      session_id  = mv_session_id
      message_id  = lines( mt_messages ) + 1
      role        = i_role
      agent       = i_agent
      prompt_type = i_prompt_type
      content     = i_content ) TO mt_messages.
  ENDMETHOD.

  METHOD parse_agent_requests.
    DATA lv_rest TYPE string.
    DATA lv_pos  TYPE i.
    DATA lv_end  TYPE i.

    lv_rest = i_orchestrator_answer.
    REPLACE ALL OCCURRENCES OF REGEX '\{\s*AGENT:' IN lv_rest WITH '{AGENT:'.

    WHILE lv_rest CS '{AGENT:'.
      FIND FIRST OCCURRENCE OF '{AGENT:' IN lv_rest MATCH OFFSET lv_pos.
      lv_rest = substring( val = lv_rest off = lv_pos + 7 ).

      FIND FIRST OCCURRENCE OF '}' IN lv_rest MATCH OFFSET lv_end.
      IF sy-subrc <> 0.
        EXIT.
      ENDIF.

      DATA(lv_command) = substring( val = lv_rest len = lv_end ).
      lv_rest = substring( val = lv_rest off = lv_end + 1 ).

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

      TRANSLATE ls_request-agent TO UPPER CASE.

      IF ls_request-agent = zcl_ai_agents_prompts=>c_agent_code_search
      OR ls_request-agent = zcl_ai_agents_prompts=>c_agent_create_obj.
        IF lines( lt_parts ) >= 2.
          ls_request-object_type = lt_parts[ 2 ].
          TRANSLATE ls_request-object_type TO UPPER CASE.
        ENDIF.
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
      ELSE.
        LOOP AT lt_parts INTO lv_part FROM 2.
          IF ls_request-relevant_prompt IS NOT INITIAL.
            ls_request-relevant_prompt = ls_request-relevant_prompt && space.
          ENDIF.
          ls_request-relevant_prompt = ls_request-relevant_prompt && lv_part.
        ENDLOOP.
      ENDIF.

      APPEND ls_request TO rt_requests.
    ENDWHILE.
  ENDMETHOD.

  METHOD build_agent_request.
    rv_prompt = zcl_ai_agents_prompts=>get_prompt_by_agent( is_request-agent )
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

    add_message(
      i_role        = 'user'
      i_agent       = is_request-agent
      i_prompt_type = 'AGENT_PROMPT'
      i_content     = rv_prompt ).
  ENDMETHOD.

  METHOD build_read_command.
    CHECK is_request-agent = zcl_ai_agents_prompts=>c_agent_code_search.
    CHECK is_request-object_name IS NOT INITIAL.

    CASE is_request-object_type.
      WHEN 'REPS' OR 'PROG'.
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
    DATA(lv_code_context) = VALUE string( ).

    LOOP AT mt_messages INTO DATA(ls_message).
      CHECK ls_message-agent = zcl_ai_agents_prompts=>c_agent_code_reader.
      CHECK ls_message-role = 'assistant'.

      IF lv_code_context IS NOT INITIAL.
        lv_code_context = lv_code_context
                       && cl_abap_char_utilities=>newline
                       && cl_abap_char_utilities=>newline.
      ENDIF.

      lv_code_context = lv_code_context && ls_message-content.
    ENDLOOP.

    rv_prompt = |FOUND CODE:|
             && cl_abap_char_utilities=>newline
             && COND string(
                  WHEN lv_code_context IS NOT INITIAL THEN lv_code_context
                  ELSE 'No code context was resolved.' )
             && cl_abap_char_utilities=>newline
             && cl_abap_char_utilities=>newline
             && |USER PROMPT:|
             && cl_abap_char_utilities=>newline
             && mv_user_prompt.

    add_message(
      i_role        = 'user'
      i_agent       = 'FINAL'
      i_prompt_type = 'AGENT_PROMPT'
      i_content     = rv_prompt ).
  ENDMETHOD.

  METHOD get_messages.
    rt_messages = mt_messages.
  ENDMETHOD.

ENDCLASS.
