*&---------------------------------------------------------------------*
*& Report Z_EASY_AI
*&---------------------------------------------------------------------*
*& Easy AI API example with GUI popup
*&---------------------------------------------------------------------*
REPORT z_abap_ai_code.



SELECTION-SCREEN BEGIN OF BLOCK b_api WITH FRAME TITLE TEXT-001.
PARAMETERS: p_anth RADIOBUTTON GROUP api DEFAULT 'X',
            p_oai  RADIOBUTTON GROUP api.

PARAMETERS: p_dest   TYPE text255 MEMORY ID dest,
            p_model  TYPE text255 MEMORY ID model,
            p_apikey TYPE text255 MEMORY ID api.
SELECTION-SCREEN END OF BLOCK b_api.


*----------------------------------------------------------------------*
* lcl_ai_api - HTTP communication with Anthropic API
*----------------------------------------------------------------------*
CLASS lcl_ai_api DEFINITION.
  PUBLIC SECTION.
    CLASS-METHODS ask
      IMPORTING i_prompt         TYPE string
                i_dest           TYPE text255
                i_model          TYPE text255
                i_apikey         TYPE string
                i_provider       TYPE string DEFAULT 'ANTHROPIC'
                i_prompt_cache_key TYPE string OPTIONAL
      RETURNING VALUE(rv_answer) TYPE string.

  PRIVATE SECTION.
    CLASS-METHODS:
      build_payload
        IMPORTING i_prompt        TYPE string
                  i_model         TYPE text255
                  i_provider      TYPE string
                  i_prompt_cache_key TYPE string OPTIONAL
        RETURNING VALUE(rv_json)  TYPE string,

      parse_response
        IMPORTING i_json           TYPE string
                  i_provider       TYPE string
        RETURNING VALUE(rv_answer) TYPE string.
ENDCLASS.

CLASS lcl_ai_api IMPLEMENTATION.

  METHOD ask.
    DATA: payload  TYPE string,
          o_client TYPE REF TO if_http_client.
    DATA: lv_provider TYPE string,
          lv_auth     TYPE string.

    lv_provider = i_provider.
    TRANSLATE lv_provider TO UPPER CASE.
    IF lv_provider IS INITIAL.
      lv_provider = 'ANTHROPIC'.
    ENDIF.

    payload = build_payload(
      i_prompt           = i_prompt
      i_model            = i_model
      i_provider         = lv_provider
      i_prompt_cache_key = i_prompt_cache_key ).

    CALL METHOD cl_http_client=>create_by_destination
      EXPORTING  destination              = i_dest
      IMPORTING  client                   = o_client
      EXCEPTIONS destination_not_found    = 2
                 OTHERS                   = 5.

    IF sy-subrc = 2.
      rv_answer = 'Error: Destination not found (check SM59)'.
      RETURN.
    ELSEIF sy-subrc <> 0.
      rv_answer = |Error: cl_http_client rc={ sy-subrc }|.
      RETURN.
    ENDIF.

    o_client->request->set_header_field( name = 'Content-Type' value = 'application/json' ).
    IF lv_provider = 'OPENAI'.
      lv_auth = i_apikey.
      IF lv_auth CP 'Bearer *' OR lv_auth CP 'bearer *'.
        o_client->request->set_header_field( name = 'Authorization' value = lv_auth ).
      ELSE.
        o_client->request->set_header_field( name = 'Authorization' value = |Bearer { lv_auth }| ).
      ENDIF.
    ELSE.
      o_client->request->set_header_field( name = 'anthropic-version' value = '2023-06-01' ).
      o_client->request->set_header_field( name = 'x-api-key'         value = i_apikey ).
    ENDIF.
    o_client->request->set_method( 'POST' ).
    o_client->request->set_cdata( payload ).

    o_client->send(
      EXCEPTIONS http_communication_failure = 1
                 OTHERS                     = 5 ).

    IF sy-subrc <> 0.
      rv_answer = 'Error: HTTP send failed'.
      RETURN.
    ENDIF.

    o_client->receive(
      EXCEPTIONS http_communication_failure = 1
                 OTHERS                     = 4 ).

    DATA(lv_response) = o_client->response->get_cdata( ).
    rv_answer = parse_response( i_json = lv_response i_provider = lv_provider ).
  ENDMETHOD.

  METHOD build_payload.
    DATA: lv_prompt           TYPE string,
          lv_prompt_cache_key TYPE string,
          lv_provider         TYPE string,
          lv_cr               TYPE c LENGTH 1.

    lv_provider = i_provider.
    TRANSLATE lv_provider TO UPPER CASE.
    lv_cr = cl_abap_char_utilities=>cr_lf(1).

    lv_prompt = i_prompt.
    REPLACE ALL OCCURRENCES OF '\' IN lv_prompt WITH '\\'.
    REPLACE ALL OCCURRENCES OF '"' IN lv_prompt WITH '\"'.
    REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>cr_lf IN lv_prompt WITH '\n'.
    REPLACE ALL OCCURRENCES OF lv_cr IN lv_prompt WITH '\r'.
    REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>newline IN lv_prompt WITH '\n'.
    REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>form_feed IN lv_prompt WITH '\f'.
    REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>horizontal_tab IN lv_prompt WITH '\t'.

    rv_json = |{ '{' }"model": "{ i_model }", "messages": [{ '{' }"role": "user", "content": "{ lv_prompt }"{ '}' }], "max_tokens": 2000{ '}' }|.
    IF lv_provider = 'OPENAI' AND i_prompt_cache_key IS NOT INITIAL.
      lv_prompt_cache_key = i_prompt_cache_key.
      REPLACE ALL OCCURRENCES OF '\' IN lv_prompt_cache_key WITH '\\'.
      REPLACE ALL OCCURRENCES OF '"' IN lv_prompt_cache_key WITH '\"'.
      rv_json = |{ '{' }"model": "{ i_model }", "messages": [{ '{' }"role": "user", "content": "{ lv_prompt }"{ '}' }], "max_tokens": 2000, "prompt_cache_key": "{ lv_prompt_cache_key }"{ '}' }|.
    ENDIF.
  ENDMETHOD.

  METHOD parse_response.
    TYPES: BEGIN OF t_prompt_tokens_details,
             cached_tokens TYPE string,
           END OF t_prompt_tokens_details,
           BEGIN OF t_usage,
             prompt_tokens         TYPE string,
             completion_tokens     TYPE string,
             total_tokens          TYPE string,
             prompt_tokens_details TYPE t_prompt_tokens_details,
           END OF t_usage,
           BEGIN OF t_content_block,
             type TYPE string,
             text TYPE string,
           END OF t_content_block,
           t_content_blocks TYPE STANDARD TABLE OF t_content_block WITH NON-UNIQUE DEFAULT KEY,
           BEGIN OF t_anthropic_res,
             id          TYPE string,
             type        TYPE string,
             role        TYPE string,
             model       TYPE string,
             stop_reason TYPE string,
             content     TYPE t_content_blocks,
             usage       TYPE t_usage,
           END OF t_anthropic_res.

    TYPES: BEGIN OF t_openai_message,
             role              TYPE string,
             content           TYPE string,
             reasoning_content TYPE string,
           END OF t_openai_message,
           BEGIN OF t_openai_choice,
             index         TYPE string,
             message       TYPE t_openai_message,
             finish_reason TYPE string,
           END OF t_openai_choice,
           t_openai_choices TYPE STANDARD TABLE OF t_openai_choice WITH NON-UNIQUE DEFAULT KEY,
           BEGIN OF t_openai_res,
             id      TYPE string,
             object  TYPE string,
             created TYPE string,
             model   TYPE string,
             choices TYPE t_openai_choices,
             usage   TYPE t_usage,
           END OF t_openai_res.

    DATA: lv_provider     TYPE string,
          response        TYPE t_anthropic_res,
          openai_response TYPE t_openai_res,
          lv_text         TYPE string,
          lv_usage_info   TYPE string.

    lv_provider = i_provider.
    TRANSLATE lv_provider TO UPPER CASE.

    IF lv_provider = 'OPENAI'.
      /ui2/cl_json=>deserialize( EXPORTING json = i_json CHANGING data = openai_response ).
      IF openai_response-choices IS NOT INITIAL.
        lv_text = openai_response-choices[ 1 ]-message-content.
        IF openai_response-usage-total_tokens IS NOT INITIAL.
          lv_usage_info = |Tokens: prompt={ openai_response-usage-prompt_tokens } completion={ openai_response-usage-completion_tokens } total={ openai_response-usage-total_tokens } cached={ openai_response-usage-prompt_tokens_details-cached_tokens }|.
          rv_answer = lv_text && cl_abap_char_utilities=>newline && cl_abap_char_utilities=>newline && lv_usage_info.
        ELSE.
          rv_answer = lv_text.
        ENDIF.
      ELSE.
        rv_answer = i_json.
      ENDIF.
      RETURN.
    ENDIF.

    /ui2/cl_json=>deserialize( EXPORTING json = i_json CHANGING data = response ).

    IF response-content IS NOT INITIAL.
      lv_text = response-content[ 1 ]-text.
      IF response-usage-total_tokens IS NOT INITIAL.
        lv_usage_info = |Tokens: input={ response-usage-prompt_tokens } output={ response-usage-completion_tokens } total={ response-usage-total_tokens }|.
        rv_answer = lv_text && cl_abap_char_utilities=>newline && cl_abap_char_utilities=>newline && lv_usage_info.
      ELSE.
        rv_answer = lv_text.
      ENDIF.
    ELSE.
      rv_answer = i_json.
    ENDIF.
  ENDMETHOD.

ENDCLASS.

*----------------------------------------------------------------------*
* lcl_history_popup - message history popup
*----------------------------------------------------------------------*
CLASS lcl_history_popup DEFINITION.
  PUBLIC SECTION.
    METHODS constructor
      IMPORTING it_messages TYPE zcl_ai_messages=>tt_messages.

    METHODS show.

  PRIVATE SECTION.
    TYPES: ty_textedit_line(255) TYPE c,
           tt_textedit_lines     TYPE TABLE OF ty_textedit_line,
           BEGIN OF ty_history_row,
             session_id     TYPE i,
             seq            TYPE i,
             agent          TYPE string,
             request_type   TYPE string,
             answer_type    TYPE string,
             request_preview TYPE string,
             answer_preview TYPE string,
             request        TYPE string,
             answer         TYPE string,
           END OF ty_history_row,
           tt_history_rows TYPE STANDARD TABLE OF ty_history_row WITH NON-UNIQUE DEFAULT KEY.

    DATA mo_dialog   TYPE REF TO cl_gui_dialogbox_container.
    DATA mo_split    TYPE REF TO cl_gui_splitter_container.
    DATA mo_details  TYPE REF TO cl_gui_splitter_container.
    DATA mo_request  TYPE REF TO cl_gui_textedit.
    DATA mo_answer   TYPE REF TO cl_gui_textedit.
    DATA mo_salv     TYPE REF TO cl_salv_table.
    DATA mt_history  TYPE tt_history_rows.
    DATA mt_messages TYPE zcl_ai_messages=>tt_messages.

    METHODS build_history.
    METHODS configure_salv.
    METHODS on_dialog_close
      FOR EVENT close OF cl_gui_dialogbox_container.
    METHODS on_double_click
      FOR EVENT double_click OF cl_salv_events_table
      IMPORTING row column.
    METHODS show_row
      IMPORTING i_row TYPE i.
    METHODS display_text
      IMPORTING io_textedit TYPE REF TO cl_gui_textedit
                i_text      TYPE string.
    METHODS preview
      IMPORTING i_text          TYPE string
      RETURNING VALUE(rv_text) TYPE string.
ENDCLASS.

CLASS lcl_history_popup IMPLEMENTATION.

  METHOD constructor.
    mt_messages = it_messages.
  ENDMETHOD.

  METHOD show.
    build_history( ).

    CREATE OBJECT mo_dialog
      EXPORTING
        caption = 'Easy AI Message History'
        top     = 60
        left    = 80
        width   = 1300
        height  = 760
        metric  = cl_gui_dialogbox_container=>metric_pixel
      EXCEPTIONS
        OTHERS  = 1.

    SET HANDLER on_dialog_close FOR mo_dialog.

    CREATE OBJECT mo_split
      EXPORTING
        parent  = mo_dialog
        rows    = 2
        columns = 1
      EXCEPTIONS
        OTHERS  = 1.

    mo_split->set_row_height( id = 1 height = 35 ).
    mo_split->set_row_height( id = 2 height = 65 ).

    DATA(lo_top) = mo_split->get_container( row = 1 column = 1 ).
    DATA(lo_bottom) = mo_split->get_container( row = 2 column = 1 ).

    CREATE OBJECT mo_details
      EXPORTING
        parent  = lo_bottom
        rows    = 1
        columns = 2
      EXCEPTIONS
        OTHERS  = 1.

    mo_details->set_column_width( id = 1 width = 50 ).
    mo_details->set_column_width( id = 2 width = 50 ).

    DATA(lo_request) = mo_details->get_container( row = 1 column = 1 ).
    DATA(lo_answer) = mo_details->get_container( row = 1 column = 2 ).

    CREATE OBJECT mo_request
      EXPORTING parent = lo_request
      EXCEPTIONS OTHERS = 1.
    mo_request->set_toolbar_mode( 0 ).
    mo_request->set_readonly_mode( 1 ).

    CREATE OBJECT mo_answer
      EXPORTING parent = lo_answer
      EXCEPTIONS OTHERS = 1.
    mo_answer->set_toolbar_mode( 0 ).
    mo_answer->set_readonly_mode( 1 ).

    cl_salv_table=>factory(
      EXPORTING
        r_container  = lo_top
      IMPORTING
        r_salv_table = mo_salv
      CHANGING
        t_table      = mt_history ).

    configure_salv( ).

    DATA(lo_events) = mo_salv->get_event( ).
    SET HANDLER on_double_click FOR lo_events.

    mo_salv->display( ).

    IF mt_history IS NOT INITIAL.
      show_row( 1 ).
    ENDIF.

    CALL METHOD cl_gui_cfw=>flush.
  ENDMETHOD.

  METHOD build_history.
    CLEAR mt_history.

    DATA ls_row TYPE ty_history_row.
    DATA lv_request TYPE string.
    DATA lv_request_type TYPE string.
    DATA lv_request_agent TYPE string.
    DATA lv_request_session TYPE i.

    LOOP AT mt_messages INTO DATA(ls_message).
      IF ls_message-role = 'user'.
        lv_request = ls_message-content.
        lv_request_type = ls_message-prompt_type.
        lv_request_agent = ls_message-agent.
        lv_request_session = ls_message-session_id.
      ELSE.
        CLEAR ls_row.
        ls_row-session_id = ls_message-session_id.
        ls_row-seq = lines( mt_history ) + 1.
        ls_row-agent = ls_message-agent.
        ls_row-request_type = lv_request_type.
        ls_row-answer_type = ls_message-prompt_type.
        ls_row-request = lv_request.
        ls_row-answer = ls_message-content.
        IF ls_row-agent IS INITIAL.
          ls_row-agent = lv_request_agent.
        ENDIF.
        IF ls_row-session_id IS INITIAL.
          ls_row-session_id = lv_request_session.
        ENDIF.
        ls_row-request_preview = preview( ls_row-request ).
        ls_row-answer_preview = preview( ls_row-answer ).
        APPEND ls_row TO mt_history.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD configure_salv.
    DATA(lo_columns) = mo_salv->get_columns( ).
    lo_columns->set_optimize( abap_true ).

    TRY.
        lo_columns->get_column( 'SESSION_ID' )->set_short_text( 'Session' ).
        lo_columns->get_column( 'SEQ' )->set_short_text( 'No' ).
        lo_columns->get_column( 'AGENT' )->set_short_text( 'Agent' ).
        lo_columns->get_column( 'REQUEST_TYPE' )->set_medium_text( 'Prompt Type' ).
        lo_columns->get_column( 'ANSWER_TYPE' )->set_medium_text( 'Answer Type' ).
        lo_columns->get_column( 'REQUEST_PREVIEW' )->set_medium_text( 'Request' ).
        lo_columns->get_column( 'ANSWER_PREVIEW' )->set_medium_text( 'Answer' ).
        lo_columns->get_column( 'REQUEST' )->set_visible( abap_false ).
        lo_columns->get_column( 'ANSWER' )->set_visible( abap_false ).
      CATCH cx_salv_not_found.
    ENDTRY.
  ENDMETHOD.

  METHOD on_dialog_close.
    mo_dialog->free( ).
    CLEAR mo_dialog.
    CALL METHOD cl_gui_cfw=>flush.
  ENDMETHOD.

  METHOD on_double_click.
    show_row( row ).
  ENDMETHOD.

  METHOD show_row.
    READ TABLE mt_history INTO DATA(ls_row) INDEX i_row.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.

    display_text(
      io_textedit = mo_request
      i_text      = ls_row-request ).

    display_text(
      io_textedit = mo_answer
      i_text      = ls_row-answer ).
  ENDMETHOD.

  METHOD display_text.
    io_textedit->set_readonly_mode( 0 ).

    DATA lt_text TYPE tt_textedit_lines.
    DATA ls_text TYPE ty_textedit_line.
    DATA lt_raw  TYPE TABLE OF string.

    SPLIT i_text AT cl_abap_char_utilities=>newline INTO TABLE lt_raw.
    IF lt_raw IS INITIAL.
      APPEND i_text TO lt_raw.
    ENDIF.

    LOOP AT lt_raw INTO DATA(lv_raw_line).
      IF strlen( lv_raw_line ) = 0.
        CLEAR ls_text.
        APPEND ls_text TO lt_text.
      ELSE.
        WHILE strlen( lv_raw_line ) > 255.
          ls_text = lv_raw_line(255).
          APPEND ls_text TO lt_text.
          lv_raw_line = substring( val = lv_raw_line off = 255 ).
        ENDWHILE.
        ls_text = lv_raw_line.
        APPEND ls_text TO lt_text.
      ENDIF.
    ENDLOOP.

    io_textedit->set_text_as_stream( text = lt_text ).
    io_textedit->set_readonly_mode( 1 ).
  ENDMETHOD.

  METHOD preview.
    rv_text = i_text.
    REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>newline IN rv_text WITH space.
    CONDENSE rv_text.

    IF strlen( rv_text ) > 120.
      rv_text = rv_text(120).
    ENDIF.
  ENDMETHOD.

ENDCLASS.

*----------------------------------------------------------------------*
* lcl_popup - GUI popup with splitter: left=question, right=answer
*----------------------------------------------------------------------*
CLASS lcl_popup DEFINITION.
  PUBLIC SECTION.
    METHODS constructor
      IMPORTING i_dest   TYPE text255
                i_model  TYPE text255
                i_apikey TYPE string
                i_provider TYPE string.

    METHODS show.

  PRIVATE SECTION.
    TYPES: ty_textedit_line(255) TYPE c,
           tt_textedit_lines     TYPE TABLE OF ty_textedit_line.

    DATA: mv_dest     TYPE text255,
          mv_model    TYPE text255,
          mv_apikey   TYPE string,
          mv_provider TYPE string,
          mv_prompt_cache_key TYPE string,
          mv_session_counter TYPE i,
          mo_messages TYPE REF TO zcl_ai_messages,
          mt_message_history TYPE zcl_ai_messages=>tt_messages,
          mo_history  TYPE REF TO lcl_history_popup,
          mo_dialog   TYPE REF TO cl_gui_dialogbox_container,
          mo_toolbar  TYPE REF TO cl_gui_toolbar,
          mo_split    TYPE REF TO cl_gui_splitter_container,
          mo_question TYPE REF TO cl_gui_textedit,
          mo_answer   TYPE REF TO cl_gui_textedit.

    METHODS on_toolbar_click
      FOR EVENT function_selected OF cl_gui_toolbar
      IMPORTING fcode.

    METHODS on_dialog_close
      FOR EVENT close OF cl_gui_dialogbox_container.

    METHODS ask_ai.
    METHODS show_history.
    METHODS display_text
      IMPORTING i_text TYPE string.
ENDCLASS.

CLASS lcl_popup IMPLEMENTATION.

  METHOD constructor.
    mv_dest     = i_dest.
    mv_model    = i_model.
    mv_apikey   = i_apikey.
    mv_provider = i_provider.
    mv_prompt_cache_key = |{ sy-mandt }-{ sy-uname }-{ sy-datum }-{ sy-uzeit }|.
  ENDMETHOD.

  METHOD show.
    " Dialog popup container
    CREATE OBJECT mo_dialog
      EXPORTING
        caption  = 'Easy AI'
        top      = 20
        left     = 20
        width    = 1200
        height   = 620
        metric   = cl_gui_dialogbox_container=>metric_pixel
      EXCEPTIONS
        OTHERS   = 1.

    SET HANDLER on_dialog_close FOR mo_dialog.

    " Outer splitter: row1=toolbar, row2=editors
    DATA lo_outer TYPE REF TO cl_gui_splitter_container.
    CREATE OBJECT lo_outer
      EXPORTING
        parent  = mo_dialog
        rows    = 2
        columns = 1
      EXCEPTIONS
        OTHERS  = 1.

    lo_outer->set_row_height( id = 1 height = 8 ).
    lo_outer->set_row_height( id = 2 height = 92 ).

    DATA lo_toolbar_cont TYPE REF TO cl_gui_container.
    lo_toolbar_cont = lo_outer->get_container( row = 1 column = 1 ).

    DATA lo_editors_cont TYPE REF TO cl_gui_container.
    lo_editors_cont = lo_outer->get_container( row = 2 column = 1 ).

    " Toolbar
    CREATE OBJECT mo_toolbar
      EXPORTING parent = lo_toolbar_cont
      EXCEPTIONS OTHERS = 1.

    DATA: lt_events TYPE cntl_simple_events,
          ls_event  TYPE cntl_simple_event.

    ls_event-eventid    = cl_gui_toolbar=>m_id_function_selected.
    ls_event-appl_event = space.
    APPEND ls_event TO lt_events.
    mo_toolbar->set_registered_events( events = lt_events ).

    DATA lt_buttons TYPE ttb_button.
    APPEND VALUE #( function  = 'ASK'
                    icon      = CONV #( icon_execute_object )
                    butn_type = cntb_btype_button
                    text      = 'Ask AI'
                    quickinfo = 'Send question to AI' ) TO lt_buttons.
    APPEND VALUE #( function  = 'HISTORY'
                    icon      = CONV #( icon_protocol )
                    butn_type = cntb_btype_button
                    text      = 'History'
                    quickinfo = 'Show message history' ) TO lt_buttons.
    mo_toolbar->add_button_group( lt_buttons ).

    SET HANDLER on_toolbar_click FOR mo_toolbar.

    " Horizontal splitter: left=question, right=answer
    CREATE OBJECT mo_split
      EXPORTING
        parent  = lo_editors_cont
        rows    = 1
        columns = 2
      EXCEPTIONS
        OTHERS  = 1.

    mo_split->set_column_width( id = 1 width = 50 ).
    mo_split->set_column_width( id = 2 width = 50 ).

    DATA lo_left  TYPE REF TO cl_gui_container.
    DATA lo_right TYPE REF TO cl_gui_container.
    lo_left  = mo_split->get_container( row = 1 column = 1 ).
    lo_right = mo_split->get_container( row = 1 column = 2 ).

    " Question editor (left)
    CREATE OBJECT mo_question
      EXPORTING parent = lo_left
      EXCEPTIONS OTHERS = 1.
    mo_question->set_toolbar_mode( 0 ).  " 0 = toolbar off

    " Answer editor (right, readonly)
    CREATE OBJECT mo_answer
      EXPORTING parent = lo_right
      EXCEPTIONS OTHERS = 1.
    mo_answer->set_toolbar_mode( 0 ).
    mo_answer->set_readonly_mode( 1 ).

    CALL METHOD cl_gui_cfw=>flush.
  ENDMETHOD.

  METHOD on_dialog_close.
    mo_dialog->free( ).
    CLEAR mo_dialog.
    CALL METHOD cl_gui_cfw=>flush.
  ENDMETHOD.

  METHOD on_toolbar_click.
    CASE fcode.
      WHEN 'ASK'.
        ask_ai( ).
      WHEN 'HISTORY'.
        show_history( ).
    ENDCASE.
  ENDMETHOD.

  METHOD ask_ai.
    DATA lt_lines TYPE tt_textedit_lines.
    mo_question->get_text_as_stream( IMPORTING text = lt_lines ).

    DATA lv_prompt TYPE string.
    LOOP AT lt_lines INTO DATA(ls_line).
      IF lv_prompt IS NOT INITIAL.
        lv_prompt = lv_prompt && cl_abap_char_utilities=>newline.
      ENDIF.
      lv_prompt = lv_prompt && ls_line.
    ENDLOOP.
    CONDENSE lv_prompt.

    IF lv_prompt IS INITIAL.
      MESSAGE 'Please enter a question' TYPE 'I'.
      RETURN.
    ENDIF.

    mv_session_counter = mv_session_counter + 1.
    mo_messages = NEW zcl_ai_messages(
      i_user_prompt = lv_prompt
      i_session_id  = mv_session_counter ).

    CALL FUNCTION 'SAPGUI_PROGRESS_INDICATOR'
      EXPORTING percentage = 20 text = 'Asking orchestrator...'.

    DATA(lv_orchestrator_prompt) = mo_messages->build_orchestrator_request( ).
    DATA(lv_orchestrator_answer) = lcl_ai_api=>ask(
      i_prompt           = lv_orchestrator_prompt
      i_dest             = mv_dest
      i_model            = mv_model
      i_apikey           = mv_apikey
      i_provider         = mv_provider
      i_prompt_cache_key = mv_prompt_cache_key ).

    mo_messages->add_message(
      i_role        = 'assistant'
      i_agent       = zcl_ai_agents_prompts=>c_agent_orchestrator
      i_prompt_type = 'LLM_RESPONSE'
      i_content     = lv_orchestrator_answer ).

    DATA(lt_agent_requests) = mo_messages->parse_agent_requests( lv_orchestrator_answer ).
    DATA(lv_orchestrator_code_context) = zcl_ai_code_reader=>resolve_read_commands( lv_orchestrator_answer ).
    IF lv_orchestrator_code_context IS NOT INITIAL.
      DATA(lv_orchestrator_read_commands) = zcl_ai_code_reader=>extract_read_command_text( lv_orchestrator_answer ).

      mo_messages->add_message(
        i_role        = 'user'
        i_agent       = zcl_ai_agents_prompts=>c_agent_code_reader
        i_prompt_type = 'COMMAND'
        i_content     = lv_orchestrator_read_commands ).

      mo_messages->add_message(
        i_role        = 'assistant'
        i_agent       = zcl_ai_agents_prompts=>c_agent_code_reader
        i_prompt_type = 'AGENT_RESPONSE'
        i_content     = lv_orchestrator_code_context ).
    ENDIF.

    DATA(lv_answer) = lv_orchestrator_answer.

    IF lt_agent_requests IS NOT INITIAL OR lv_orchestrator_code_context IS NOT INITIAL.
      DATA(lv_index) = 0.
      DATA(lv_total) = lines( lt_agent_requests ).

      LOOP AT lt_agent_requests INTO DATA(ls_agent_request).
        lv_index = lv_index + 1.
        DATA(lv_percentage) = 50.
        IF lv_total > 0.
          lv_percentage = 20 + ( lv_index * 50 / lv_total ).
        ENDIF.

        CALL FUNCTION 'SAPGUI_PROGRESS_INDICATOR'
          EXPORTING percentage = lv_percentage
                    text       = |Asking agent { ls_agent_request-agent }...|.

        DATA(lv_agent_prompt) = mo_messages->build_agent_request( ls_agent_request ).
        DATA(lv_agent_answer) = lcl_ai_api=>ask(
          i_prompt           = lv_agent_prompt
          i_dest             = mv_dest
          i_model            = mv_model
          i_apikey           = mv_apikey
          i_provider         = mv_provider
          i_prompt_cache_key = mv_prompt_cache_key ).

        mo_messages->add_message(
          i_role        = 'assistant'
          i_agent       = ls_agent_request-agent
          i_prompt_type = 'LLM_RESPONSE'
          i_content     = lv_agent_answer ).

        DATA(lv_agent_code_context) = zcl_ai_code_reader=>resolve_read_commands( lv_agent_answer ).
        IF lv_agent_code_context IS NOT INITIAL.
          DATA(lv_agent_read_commands) = zcl_ai_code_reader=>extract_read_command_text( lv_agent_answer ).

          mo_messages->add_message(
            i_role        = 'user'
            i_agent       = zcl_ai_agents_prompts=>c_agent_code_reader
            i_prompt_type = 'COMMAND'
            i_content     = lv_agent_read_commands ).

          mo_messages->add_message(
            i_role        = 'assistant'
            i_agent       = zcl_ai_agents_prompts=>c_agent_code_reader
            i_prompt_type = 'AGENT_RESPONSE'
            i_content     = lv_agent_code_context ).
        ENDIF.
      ENDLOOP.

      CALL FUNCTION 'SAPGUI_PROGRESS_INDICATOR'
        EXPORTING percentage = 85 text = 'Asking AI with agent context...'.

      DATA(lv_final_prompt) = mo_messages->build_final_request( ).
      lv_answer = lcl_ai_api=>ask(
        i_prompt           = lv_final_prompt
        i_dest             = mv_dest
        i_model            = mv_model
        i_apikey           = mv_apikey
        i_provider         = mv_provider
        i_prompt_cache_key = mv_prompt_cache_key ).

      mo_messages->add_message(
        i_role        = 'assistant'
        i_agent       = 'FINAL'
        i_prompt_type = 'LLM_RESPONSE'
        i_content     = lv_answer ).
    ENDIF.

    APPEND LINES OF mo_messages->get_messages( ) TO mt_message_history.

    CALL FUNCTION 'SAPGUI_PROGRESS_INDICATOR'
      EXPORTING percentage = 0 text = ''.

    display_text( lv_answer ).
  ENDMETHOD.

  METHOD show_history.
    IF mt_message_history IS INITIAL.
      MESSAGE 'No message history yet' TYPE 'I'.
      RETURN.
    ENDIF.

    mo_history = NEW lcl_history_popup( mt_message_history ).
    mo_history->show( ).
  ENDMETHOD.

  METHOD display_text.
    mo_answer->set_readonly_mode( 0 ).

    DATA lt_answer TYPE tt_textedit_lines.
    DATA ls_answer TYPE ty_textedit_line.
    DATA lt_raw    TYPE TABLE OF string.
    SPLIT i_text AT cl_abap_char_utilities=>newline INTO TABLE lt_raw.
    IF lt_raw IS INITIAL.
      APPEND i_text TO lt_raw.
    ENDIF.
    LOOP AT lt_raw INTO DATA(lv_raw_line).
      IF strlen( lv_raw_line ) = 0.
        CLEAR ls_answer.
        APPEND ls_answer TO lt_answer.
      ELSE.
        WHILE strlen( lv_raw_line ) > 255.
          ls_answer = lv_raw_line(255).
          APPEND ls_answer TO lt_answer.
          lv_raw_line = substring( val = lv_raw_line off = 255 ).
        ENDWHILE.
        ls_answer = lv_raw_line.
        APPEND ls_answer TO lt_answer.
      ENDIF.
    ENDLOOP.

    mo_answer->set_text_as_stream( text = lt_answer ).
    mo_answer->set_readonly_mode( 1 ).

    CALL METHOD cl_gui_cfw=>flush.
  ENDMETHOD.

ENDCLASS.

*----------------------------------------------------------------------*
* Global variables
*----------------------------------------------------------------------*
DATA go_popup TYPE REF TO lcl_popup.

*----------------------------------------------------------------------*
* INITIALIZATION - suppress F8 (ONLI) button
*----------------------------------------------------------------------*
INITIALIZATION.
  DATA lt_excl TYPE TABLE OF sy-ucomm.
  APPEND 'ONLI' TO lt_excl.
  CALL FUNCTION 'RS_SET_SELSCREEN_STATUS'
    EXPORTING  p_status  = sy-pfkey
    TABLES     p_exclude = lt_excl.

*----------------------------------------------------------------------*
* AT SELECTION-SCREEN - open popup on Enter
*----------------------------------------------------------------------*
AT SELECTION-SCREEN.
  CHECK sy-ucomm IS INITIAL OR sy-ucomm = 'UCCHECK'.

  go_popup = NEW lcl_popup(
    i_dest   = p_dest
    i_model  = p_model
    i_apikey = CONV string( p_apikey )
    i_provider = COND string( WHEN p_oai = 'X' THEN 'OPENAI' ELSE 'ANTHROPIC' ) ).

  go_popup->show( ).

*----------------------------------------------------------------------*
* START-OF-SELECTION - never reached (F8 suppressed)
*----------------------------------------------------------------------*
START-OF-SELECTION.
