
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
          lv_usage_info = |---| && cl_abap_char_utilities=>newline
                       && |Tokens: prompt={ openai_response-usage-prompt_tokens } completion={ openai_response-usage-completion_tokens } total={ openai_response-usage-total_tokens } cached={ openai_response-usage-prompt_tokens_details-cached_tokens }|.
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
        lv_usage_info = |---| && cl_abap_char_utilities=>newline
                     && |Tokens: input={ response-usage-prompt_tokens } output={ response-usage-completion_tokens } total={ response-usage-total_tokens }|.
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
           tt_html               TYPE STANDARD TABLE OF w3html WITH NON-UNIQUE DEFAULT KEY,
           BEGIN OF ty_history_row,
             session_id     TYPE i,
             seq            TYPE i,
             request_type   TYPE string,
             owner          TYPE string,
             answer_type    TYPE string,
             prompt_tokens  TYPE string,
             completion_tokens TYPE string,
             total_tokens   TYPE string,
             cached_tokens  TYPE string,
             request_preview TYPE string,
             answer_preview TYPE string,
             request        TYPE string,
             answer         TYPE string,
             rowcolor(4)    TYPE c,
            END OF ty_history_row,
           tt_history_rows TYPE STANDARD TABLE OF ty_history_row WITH NON-UNIQUE DEFAULT KEY.

    DATA mo_dialog   TYPE REF TO cl_gui_dialogbox_container.
    DATA mo_split    TYPE REF TO cl_gui_splitter_container.
    DATA mo_details  TYPE REF TO cl_gui_splitter_container.
    DATA mo_request  TYPE REF TO cl_gui_html_viewer.
    DATA mo_answer   TYPE REF TO cl_gui_html_viewer.
    DATA mo_alv      TYPE REF TO cl_gui_alv_grid.
    DATA mt_history  TYPE tt_history_rows.
    DATA mt_messages TYPE zcl_ai_messages=>tt_messages.

    METHODS build_history.
    METHODS create_alv
      IMPORTING io_parent TYPE REF TO cl_gui_container.
    METHODS extract_usage
      IMPORTING i_text TYPE string
      CHANGING  cs_row TYPE ty_history_row.
    METHODS on_dialog_close
      FOR EVENT close OF cl_gui_dialogbox_container.
    METHODS on_double_click
      FOR EVENT double_click OF cl_gui_alv_grid
      IMPORTING es_row_no e_column.
    METHODS show_row
      IMPORTING i_row TYPE i.
    METHODS display_text
      IMPORTING io_viewer TYPE REF TO cl_gui_html_viewer
                i_text      TYPE string.
    METHODS source_text_to_html
      IMPORTING i_text          TYPE string
      RETURNING VALUE(rv_html) TYPE string.
    METHODS escape_html
      IMPORTING i_text          TYPE string
      RETURNING VALUE(rv_text) TYPE string.
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
        width   = 1400
        height  = 800
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

    CREATE OBJECT mo_answer
      EXPORTING parent = lo_answer
      EXCEPTIONS OTHERS = 1.

    create_alv( lo_top ).

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
    DATA lv_request_message_id TYPE i.
    DATA lv_has_request TYPE abap_bool.

    LOOP AT mt_messages INTO DATA(ls_message).
      IF ls_message-role = 'user'.
        IF lv_has_request = abap_true.
          CLEAR ls_row.
          ls_row-session_id = lv_request_session.
          ls_row-seq = lv_request_message_id.
          ls_row-owner = lv_request_agent.
          ls_row-request_type = lv_request_type.
          ls_row-request = lv_request.
          ls_row-request_preview = preview( ls_row-request ).
          APPEND ls_row TO mt_history.
        ENDIF.

        lv_request = ls_message-content.
        lv_request_type = ls_message-prompt_type.
        lv_request_agent = ls_message-agent.
        lv_request_session = ls_message-session_id.
        lv_request_message_id = ls_message-message_id.
        lv_has_request = abap_true.
      ELSE.
        CLEAR ls_row.
        ls_row-session_id = ls_message-session_id.
        IF lv_request_message_id IS INITIAL.
          ls_row-seq = ls_message-message_id.
        ELSE.
          ls_row-seq = lv_request_message_id.
        ENDIF.
        ls_row-owner = ls_message-agent.
        ls_row-request_type = lv_request_type.
        ls_row-answer_type = ls_message-prompt_type.
        ls_row-request = lv_request.
        ls_row-answer = ls_message-content.
        IF ls_row-owner IS INITIAL.
          ls_row-owner = lv_request_agent.
        ENDIF.
        IF ls_row-session_id IS INITIAL.
          ls_row-session_id = lv_request_session.
        ENDIF.
        extract_usage(
          EXPORTING
            i_text = ls_row-answer
          CHANGING
            cs_row = ls_row ).
        DATA(lv_answer_upper) = ls_row-answer.
        TRANSLATE lv_answer_upper TO UPPER CASE.
        CONDENSE lv_answer_upper.
        IF lv_answer_upper CP 'ERROR:*'
        OR lv_answer_upper CP 'SOURCE FOR PROGRAM * WAS NOT FOUND*'
        OR lv_answer_upper CP 'SOURCE FOR PROGRAM * CANNOT BE READ*'
        OR lv_answer_upper CP 'RESOLVED {READ*: SOURCE FOR PROGRAM * WAS NOT FOUND*'
        OR lv_answer_upper CP 'RESOLVED {READ*: SOURCE FOR PROGRAM * CANNOT BE READ*'
        OR lv_answer_upper CP '* WAS NOT FOUND*'
        OR lv_answer_upper CP 'METHOD * WAS NOT FOUND*'
        OR lv_answer_upper CP 'METHOD COMMAND IS INCOMPLETE*'
        OR lv_answer_upper CP 'NO CODE CONTEXT WAS RESOLVED*'.
          ls_row-rowcolor = 'C201'. " red
        ELSEIF ls_row-prompt_tokens IS NOT INITIAL
            OR ls_row-total_tokens IS NOT INITIAL
            OR ls_row-answer_type = 'LLM_RESPONSE'
            OR ls_row-answer_type = 'FINAL_ANSWER'.
          ls_row-rowcolor = 'C110'. " blue
        ENDIF.
        ls_row-request_preview = preview( ls_row-request ).
        ls_row-answer_preview = preview( ls_row-answer ).
        APPEND ls_row TO mt_history.
        CLEAR: lv_request, lv_request_type, lv_request_agent, lv_request_session, lv_request_message_id.
        lv_has_request = abap_false.
      ENDIF.
    ENDLOOP.

    IF lv_has_request = abap_true.
      CLEAR ls_row.
      ls_row-session_id = lv_request_session.
      ls_row-seq = lv_request_message_id.
      ls_row-owner = lv_request_agent.
      ls_row-request_type = lv_request_type.
      ls_row-request = lv_request.
      ls_row-request_preview = preview( ls_row-request ).
      APPEND ls_row TO mt_history.
    ENDIF.
  ENDMETHOD.

  METHOD extract_usage.
    FIND FIRST OCCURRENCE OF REGEX 'prompt=([0-9]+)' IN i_text SUBMATCHES cs_row-prompt_tokens.
    IF cs_row-prompt_tokens IS INITIAL.
      FIND FIRST OCCURRENCE OF REGEX 'input=([0-9]+)' IN i_text SUBMATCHES cs_row-prompt_tokens.
    ENDIF.

    FIND FIRST OCCURRENCE OF REGEX 'completion=([0-9]+)' IN i_text SUBMATCHES cs_row-completion_tokens.
    IF cs_row-completion_tokens IS INITIAL.
      FIND FIRST OCCURRENCE OF REGEX 'output=([0-9]+)' IN i_text SUBMATCHES cs_row-completion_tokens.
    ENDIF.

    FIND FIRST OCCURRENCE OF REGEX 'total=([0-9]+)' IN i_text SUBMATCHES cs_row-total_tokens.
    FIND FIRST OCCURRENCE OF REGEX 'cached=([0-9]+)' IN i_text SUBMATCHES cs_row-cached_tokens.
  ENDMETHOD.

  METHOD create_alv.
    DATA lt_fcat TYPE lvc_t_fcat.
    DATA ls_fc   TYPE lvc_s_fcat.
    DATA ls_layo TYPE lvc_s_layo.

    CLEAR ls_fc. ls_fc-fieldname = 'SESSION_ID'. ls_fc-coltext = 'Session'.
    ls_fc-outputlen = 7. APPEND ls_fc TO lt_fcat.
    CLEAR ls_fc. ls_fc-fieldname = 'SEQ'. ls_fc-coltext = 'Q#'.
    ls_fc-outputlen = 5. ls_fc-just = 'R'. APPEND ls_fc TO lt_fcat.
    CLEAR ls_fc. ls_fc-fieldname = 'REQUEST_TYPE'. ls_fc-coltext = 'Prompt Type'.
    ls_fc-outputlen = 14. APPEND ls_fc TO lt_fcat.
    CLEAR ls_fc. ls_fc-fieldname = 'OWNER'. ls_fc-coltext = 'Owner'.
    ls_fc-outputlen = 14. APPEND ls_fc TO lt_fcat.
    CLEAR ls_fc. ls_fc-fieldname = 'ANSWER_TYPE'. ls_fc-coltext = 'Answer Type'.
    ls_fc-outputlen = 14. APPEND ls_fc TO lt_fcat.
    CLEAR ls_fc. ls_fc-fieldname = 'PROMPT_TOKENS'. ls_fc-coltext = 'Input'.
    ls_fc-outputlen = 8. ls_fc-just = 'R'. APPEND ls_fc TO lt_fcat.
    CLEAR ls_fc. ls_fc-fieldname = 'COMPLETION_TOKENS'. ls_fc-coltext = 'Output'.
    ls_fc-outputlen = 8. ls_fc-just = 'R'. APPEND ls_fc TO lt_fcat.
    CLEAR ls_fc. ls_fc-fieldname = 'TOTAL_TOKENS'. ls_fc-coltext = 'Total'.
    ls_fc-outputlen = 8. ls_fc-just = 'R'. APPEND ls_fc TO lt_fcat.
    CLEAR ls_fc. ls_fc-fieldname = 'CACHED_TOKENS'. ls_fc-coltext = 'Cached'.
    ls_fc-outputlen = 8. ls_fc-just = 'R'. APPEND ls_fc TO lt_fcat.
    CLEAR ls_fc. ls_fc-fieldname = 'REQUEST_PREVIEW'. ls_fc-coltext = 'Request'.
    ls_fc-outputlen = 45. APPEND ls_fc TO lt_fcat.
    CLEAR ls_fc. ls_fc-fieldname = 'ANSWER_PREVIEW'. ls_fc-coltext = 'Answer'.
    ls_fc-outputlen = 55. APPEND ls_fc TO lt_fcat.
    CLEAR ls_fc. ls_fc-fieldname = 'REQUEST'. ls_fc-no_out = abap_true.
    APPEND ls_fc TO lt_fcat.
    CLEAR ls_fc. ls_fc-fieldname = 'ANSWER'. ls_fc-no_out = abap_true.
    APPEND ls_fc TO lt_fcat.
    CLEAR ls_fc. ls_fc-fieldname = 'ROWCOLOR'. ls_fc-no_out = abap_true.
    APPEND ls_fc TO lt_fcat.

    ls_layo-zebra      = abap_true.
    ls_layo-info_fname = 'ROWCOLOR'.
    ls_layo-cwidth_opt = abap_true.
    ls_layo-sel_mode   = 'A'.

    mo_alv = NEW cl_gui_alv_grid( i_parent = io_parent ).
    SET HANDLER on_double_click FOR mo_alv.

    mo_alv->set_table_for_first_display(
      EXPORTING
        is_layout       = ls_layo
        i_save          = 'A'
        i_default       = 'X'
      CHANGING
        it_fieldcatalog = lt_fcat
        it_outtab       = mt_history ).
  ENDMETHOD.

  METHOD on_dialog_close.
    mo_dialog->free( ).
    CLEAR mo_dialog.
    CALL METHOD cl_gui_cfw=>flush.
  ENDMETHOD.

  METHOD on_double_click.
    show_row( es_row_no-row_id ).
  ENDMETHOD.

  METHOD show_row.
    READ TABLE mt_history INTO DATA(ls_row) INDEX i_row.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.

    display_text(
      io_viewer = mo_request
      i_text    = ls_row-request ).

    display_text(
      io_viewer = mo_answer
      i_text    = ls_row-answer ).
  ENDMETHOD.

  METHOD display_text.
    DATA lv_html TYPE string.
    DATA(lv_text_upper) = i_text.
    TRANSLATE lv_text_upper TO UPPER CASE.

    IF lv_text_upper CS 'RESOLVED {READ'
    OR lv_text_upper CS 'SOURCE FOR PROGRAM'
    OR lv_text_upper CS 'SOURCE FOR CLASS'
    OR lv_text_upper CS 'SOURCE FOR METHOD'.
      lv_html = source_text_to_html( i_text ).
    ELSE.
      DATA(lv_escaped_text) = escape_html( i_text ).
      REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>cr_lf IN lv_escaped_text WITH '<br>'.
      REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>newline IN lv_escaped_text WITH '<br>'.

      lv_html = |<!doctype html><html><head><meta charset="utf-8">|
             && |<style>body\{font-family:"Segoe UI",Arial,sans-serif;font-size:13px;margin:8px;\}|
             && |.log\{font-family:Consolas,"Courier New",monospace;line-height:1.3;\}|
             && |</style></head><body><div class="log">|
             && lv_escaped_text
             && |</div></body></html>|.
    ENDIF.

    DATA lt_html TYPE tt_html.
    DATA ls_html TYPE w3html.
    DATA lv_offset TYPE i.

    WHILE lv_offset < strlen( lv_html ).
      CLEAR ls_html.
      ls_html-line = substring(
        val = lv_html
        off = lv_offset
        len = nmin( val1 = 255 val2 = strlen( lv_html ) - lv_offset ) ).
      APPEND ls_html TO lt_html.
      lv_offset = lv_offset + 255.
    ENDWHILE.

    DATA lv_url TYPE c LENGTH 255.
    io_viewer->load_data(
      EXPORTING
        type         = 'text'
        subtype      = 'html'
      IMPORTING
        assigned_url = lv_url
      CHANGING
        data_table   = lt_html
      EXCEPTIONS
        OTHERS       = 1 ).

    io_viewer->show_url(
      EXPORTING url = lv_url
      EXCEPTIONS OTHERS = 1 ).
  ENDMETHOD.

  METHOD source_text_to_html.
    DATA lv_source TYPE string.
    DATA lv_rows TYPE string.
    DATA lv_lno TYPE i.
    DATA lt_lines TYPE STANDARD TABLE OF string WITH NON-UNIQUE DEFAULT KEY.

    lv_source = i_text.
    REPLACE ALL OCCURRENCES OF REGEX 'Resolved \{READ[^\n\r]*\}:\s*' IN lv_source WITH ''.
    REPLACE ALL OCCURRENCES OF REGEX 'Source for program [^:\n\r]*:\s*' IN lv_source WITH ''.
    REPLACE ALL OCCURRENCES OF REGEX 'Source for class [^:\n\r]*:\s*' IN lv_source WITH ''.
    REPLACE ALL OCCURRENCES OF REGEX 'Source for method [^:\n\r]*:\s*' IN lv_source WITH ''.
    REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>cr_lf IN lv_source WITH cl_abap_char_utilities=>newline.

    SPLIT lv_source AT cl_abap_char_utilities=>newline INTO TABLE lt_lines.

    LOOP AT lt_lines INTO DATA(lv_line).
      lv_lno = lv_lno + 1.
      lv_rows = lv_rows
             && |<tr><td class="ln">{ lv_lno }</td>|
             && |<td class="cd">{ escape_html( lv_line ) }</td></tr>|.
    ENDLOOP.

    rv_html = |<!doctype html><html><head><meta charset="utf-8">|
           && |<style>body\{margin:0;background:#fff;color:#1e1e1e;font:12px/1.5 Consolas,monospace\}|
           && |table\{border-collapse:collapse;width:100%\}tr:hover td\{background:#f0f4fa\}|
           && |.ln\{color:#aaa;text-align:right;padding:1px 10px 1px 5px;min-width:42px;|
           && |border-right:1px solid #e0e0e0;white-space:nowrap;background:#fafafa;user-select:none\}|
           && |.cd\{padding:1px 8px;white-space:pre\}</style></head><body>|
           && |<table><tbody>| && lv_rows && |</tbody></table></body></html>|.
  ENDMETHOD.

  METHOD escape_html.
    rv_text = i_text.
    REPLACE ALL OCCURRENCES OF '&' IN rv_text WITH '&amp;'.
    REPLACE ALL OCCURRENCES OF '<' IN rv_text WITH '&lt;'.
    REPLACE ALL OCCURRENCES OF '>' IN rv_text WITH '&gt;'.
    REPLACE ALL OCCURRENCES OF '"' IN rv_text WITH '&quot;'.
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
           tt_textedit_lines     TYPE TABLE OF ty_textedit_line,
           tt_html               TYPE STANDARD TABLE OF w3html WITH NON-UNIQUE DEFAULT KEY.

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
          mo_answer   TYPE REF TO cl_gui_html_viewer.

    METHODS on_toolbar_click
      FOR EVENT function_selected OF cl_gui_toolbar
      IMPORTING fcode.

    METHODS on_dialog_close
      FOR EVENT close OF cl_gui_dialogbox_container.

    METHODS ask_ai.
    METHODS show_history.
    METHODS display_text
      IMPORTING i_text TYPE string.
    METHODS display_answer
      IMPORTING i_answer TYPE string
                i_source TYPE string OPTIONAL.
    METHODS source_to_html
      IMPORTING i_source       TYPE string
                i_title        TYPE string
      RETURNING VALUE(rv_html) TYPE string.
    METHODS normalize_markdown
      IMPORTING i_text          TYPE string
      RETURNING VALUE(rv_text) TYPE string.
    METHODS render_abap_blocks
      IMPORTING i_text          TYPE string
      RETURNING VALUE(rv_text) TYPE string.
    METHODS source_block_to_html
      IMPORTING i_source       TYPE string
                i_title        TYPE string
      RETURNING VALUE(rv_html) TYPE string.
    METHODS render_markdown_text
      IMPORTING i_text          TYPE string
      RETURNING VALUE(rv_html) TYPE string.
    METHODS render_inline_markdown
      IMPORTING i_text          TYPE string
      RETURNING VALUE(rv_html) TYPE string.
    METHODS code_block_to_html
      IMPORTING i_code          TYPE string
      RETURNING VALUE(rv_html) TYPE string.
    METHODS escape_html
      IMPORTING i_text          TYPE string
      RETURNING VALUE(rv_text) TYPE string.
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
        width    = 1400
        height   = 800
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

    mo_split->set_column_width( id = 1 width = 40 ).
    mo_split->set_column_width( id = 2 width = 60 ).

    DATA lo_left  TYPE REF TO cl_gui_container.
    DATA lo_right TYPE REF TO cl_gui_container.
    lo_left  = mo_split->get_container( row = 1 column = 1 ).
    lo_right = mo_split->get_container( row = 1 column = 2 ).

    " Question editor (left)
    CREATE OBJECT mo_question
      EXPORTING parent = lo_left
      EXCEPTIONS OTHERS = 1.
    mo_question->set_toolbar_mode( 0 ).  " 0 = toolbar off

    " Answer viewer (right)
    CREATE OBJECT mo_answer
      EXPORTING parent = lo_right
      EXCEPTIONS OTHERS = 1.

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
    DATA(lv_orchestrator_upper) = lv_orchestrator_answer.
    TRANSLATE lv_orchestrator_upper TO UPPER CASE.
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
    DATA lv_resolved_code TYPE string.

    IF lt_agent_requests IS INITIAL
    AND lv_orchestrator_code_context IS INITIAL
    AND lv_orchestrator_upper CS 'AGENT'.
      lv_answer = |Error: Orchestrator returned an agent command that could not be parsed. Check History for the raw response.|.
    ENDIF.

    IF lt_agent_requests IS NOT INITIAL OR lv_orchestrator_code_context IS NOT INITIAL.
      DATA(lv_index) = 0.
      DATA(lv_total) = lines( lt_agent_requests ).
      DATA lt_done_read_commands TYPE STANDARD TABLE OF string WITH NON-UNIQUE DEFAULT KEY.

      IF lv_orchestrator_code_context IS NOT INITIAL.
        APPEND lv_orchestrator_read_commands TO lt_done_read_commands.
      ENDIF.

      LOOP AT lt_agent_requests INTO DATA(ls_agent_request).
        lv_index = lv_index + 1.
        DATA(lv_percentage) = 50.
        IF lv_total > 0.
          lv_percentage = 20 + ( lv_index * 50 / lv_total ).
        ENDIF.

        DATA(lv_direct_read_command) = mo_messages->build_read_command( ls_agent_request ).
        IF lv_direct_read_command IS NOT INITIAL.
          READ TABLE lt_done_read_commands
            WITH KEY table_line = lv_direct_read_command
            TRANSPORTING NO FIELDS.
          IF sy-subrc = 0.
            CONTINUE.
          ENDIF.
          APPEND lv_direct_read_command TO lt_done_read_commands.

          CALL FUNCTION 'SAPGUI_PROGRESS_INDICATOR'
            EXPORTING percentage = lv_percentage
                      text       = |Reading code { ls_agent_request-object_name }...|.

          DATA(lv_direct_code_context) = zcl_ai_code_reader=>resolve_read_commands( lv_direct_read_command ).

          mo_messages->add_message(
            i_role        = 'user'
            i_agent       = zcl_ai_agents_prompts=>c_agent_code_reader
            i_prompt_type = 'COMMAND'
            i_content     = lv_direct_read_command ).

          mo_messages->add_message(
            i_role        = 'assistant'
            i_agent       = zcl_ai_agents_prompts=>c_agent_code_reader
            i_prompt_type = 'AGENT_RESPONSE'
            i_content     = lv_direct_code_context ).

          CONTINUE.
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

      DATA(lv_only_code_search) = abap_true.
      LOOP AT lt_agent_requests INTO ls_agent_request.
        IF ls_agent_request-agent <> zcl_ai_agents_prompts=>c_agent_code_search.
          lv_only_code_search = abap_false.
          EXIT.
        ENDIF.
        IF ls_agent_request-relevant_prompt IS NOT INITIAL.
          lv_only_code_search = abap_false.
          EXIT.
        ENDIF.
      ENDLOOP.

      IF mo_messages->has_text_after_agent_commands( lv_orchestrator_answer ) = abap_true.
        lv_only_code_search = abap_false.
      ENDIF.

      DATA(lv_agent_error) = mo_messages->get_agent_error( ).
      IF lv_agent_error IS NOT INITIAL.
        lv_answer = lv_agent_error.
      ELSEIF lt_agent_requests IS NOT INITIAL
      AND lv_only_code_search = abap_true.
        DATA(lv_code_only) = mo_messages->get_resolved_code( ).
        lv_answer = source_to_html(
          i_source = lv_code_only
          i_title  = 'ABAP Source' ).
      ELSE.
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

        lv_resolved_code = mo_messages->get_resolved_code( ).
      ENDIF.

      mo_messages->add_message(
        i_role        = 'assistant'
        i_agent       = 'FINAL'
        i_prompt_type = 'FINAL_ANSWER'
        i_content     = lv_answer ).
    ENDIF.

    APPEND LINES OF mo_messages->get_messages( ) TO mt_message_history.

    CALL FUNCTION 'SAPGUI_PROGRESS_INDICATOR'
      EXPORTING percentage = 0 text = ''.

    display_answer(
      i_answer = lv_answer
      i_source = lv_resolved_code ).
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
    display_answer( i_answer = i_text ).
  ENDMETHOD.

  METHOD display_answer.
    DATA lv_html TYPE string.
    DATA lv_text_upper TYPE string.

    lv_text_upper = i_answer.
    TRANSLATE lv_text_upper TO UPPER CASE.

    IF lv_text_upper CS '<!DOCTYPE HTML'
    OR lv_text_upper CS '<HTML'.
      lv_html = i_answer.
    ELSE.
      DATA(lv_render_text) = render_abap_blocks( i_answer ).
      DATA(lv_source_html) = source_block_to_html(
        i_source = i_source
        i_title  = 'Source code from code_agent' ).

      lv_html = |<!doctype html><html><head><meta charset="utf-8">|
             && |<style>body\{font-family:"Segoe UI",Arial,sans-serif;font-size:14px;margin:0;|
             && |min-height:100vh;background:linear-gradient(135deg,#f8fbff 0%,#eef6ff 45%,#f7fff9 100%);|
             && |color:#1f2933;\}|
             && |.answer\{white-space:pre-wrap;font-family:"Segoe UI",Arial,sans-serif;line-height:1.45;|
             && |margin:14px;padding:16px 18px;background:rgba(255,255,255,.88);border:1px solid #dce8f6;|
             && |box-shadow:0 2px 10px rgba(56,96,140,.10);\}|
             && |.md_h\{display:block;font-size:17px;font-weight:700;color:#23476f;margin:4px 0 8px\}|
             && |.md_li\{display:block;margin:2px 0 2px 18px;text-indent:-18px\}|
             && |code\{font-family:Consolas,monospace;background:#eef3f8;border:1px solid #d7e0ea;|
             && |padding:0 4px;color:#18324a\}|
             && |strong\{font-weight:700\}|
             && |.tokens\{display:inline-block;color:#005ea8;font-weight:700;background:#e8f3ff;|
             && |border:1px solid #b9dcff;padding:3px 7px;margin-top:6px;\}|
             && |.code_tbl\{border-collapse:collapse;width:100%;font:12px/1.5 Consolas,monospace;|
             && |background:#fff;border:1px solid #d7e0ea;margin:10px 0;\}|
             && |.source_title\{font-weight:700;color:#23476f;margin:14px 0 6px\}|
             && |.code_tbl tr:hover td\{background:#f0f4fa\}|
             && |.ln\{color:#aaa;text-align:right;padding:1px 10px 1px 5px;min-width:42px;|
             && |border-right:1px solid #e0e0e0;white-space:nowrap;background:#fafafa;user-select:none;\}|
             && |.cd\{padding:1px 8px;white-space:pre;\}|
             && |</style></head><body><div class="answer">|
             && lv_render_text
             && lv_source_html
             && |</div></body></html>|.
    ENDIF.

    DATA lt_html TYPE tt_html.
    DATA ls_html TYPE w3html.
    DATA lv_offset TYPE i.

    WHILE lv_offset < strlen( lv_html ).
      CLEAR ls_html.
      ls_html-line = substring(
        val = lv_html
        off = lv_offset
        len = nmin( val1 = 255 val2 = strlen( lv_html ) - lv_offset ) ).
      APPEND ls_html TO lt_html.
      lv_offset = lv_offset + 255.
    ENDWHILE.

    DATA lv_url TYPE c LENGTH 255.
    mo_answer->load_data(
      EXPORTING
        type         = 'text'
        subtype      = 'html'
      IMPORTING
        assigned_url = lv_url
      CHANGING
        data_table   = lt_html
      EXCEPTIONS
        OTHERS       = 1 ).

    mo_answer->show_url(
      EXPORTING url = lv_url
      EXCEPTIONS OTHERS = 1 ).

    CALL METHOD cl_gui_cfw=>flush.
  ENDMETHOD.

  METHOD source_to_html.
    DATA lv_rows TYPE string.
    DATA lv_lno TYPE i.
    DATA lt_lines TYPE STANDARD TABLE OF string WITH NON-UNIQUE DEFAULT KEY.

    SPLIT i_source AT cl_abap_char_utilities=>newline INTO TABLE lt_lines.

    LOOP AT lt_lines INTO DATA(lv_line).
      lv_lno = lv_lno + 1.
      lv_rows = lv_rows
             && |<tr><td class="ln">{ lv_lno }</td>|
             && |<td class="cd">{ escape_html( i_text = lv_line ) }</td></tr>|.
    ENDLOOP.

    DATA(lv_title) = escape_html( i_text = i_title ).

    rv_html = |<!DOCTYPE html><html><head><meta charset="utf-8"><style>|
           && |*\{margin:0;padding:0;box-sizing:border-box\}|
           && |body\{background:#ffffff;color:#1e1e1e;font:12px/1.5 Consolas,monospace\}|
           && |.hdr\{background:#f3f3f3;padding:5px 12px;border-bottom:1px solid #ddd;|
           && |color:#444;font-size:11px;display:flex;gap:16px;flex-wrap:wrap\}|
           && |.ttl\{color:#0066aa;font-weight:bold\}|
           && |table\{border-collapse:collapse;width:100%\}|
           && |tr:hover td\{background:#f0f4fa\}|
           && |.ln\{color:#aaa;text-align:right;padding:1px 10px 1px 5px;|
           && |user-select:none;min-width:42px;border-right:1px solid #e0e0e0;|
           && |white-space:nowrap;background:#fafafa\}|
           && |.cd\{padding:1px 8px;white-space:pre\}|
           && |</style></head><body>|
           && |<div class="hdr"><span class="ttl">{ lv_title }</span></div>|
           && |<table><tbody>| && lv_rows && |</tbody></table></body></html>|.
  ENDMETHOD.

  METHOD normalize_markdown.
    rv_text = i_text.

    DATA(lv_nl) = cl_abap_char_utilities=>newline.

    REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>cr_lf IN rv_text WITH lv_nl.
    REPLACE ALL OCCURRENCES OF REGEX '\s+(#{1,6})\s+' IN rv_text WITH |{ lv_nl }{ lv_nl }$1 |.
    REPLACE ALL OCCURRENCES OF '## Overall Assessment ' IN rv_text WITH |## Overall Assessment{ lv_nl }|.
    REPLACE ALL OCCURRENCES OF '## Strengths ' IN rv_text WITH |## Strengths{ lv_nl }|.
    REPLACE ALL OCCURRENCES OF '## Areas for Improvement ' IN rv_text WITH |## Areas for Improvement{ lv_nl }|.
    REPLACE ALL OCCURRENCES OF '## Specific Recommendations ' IN rv_text WITH |## Specific Recommendations{ lv_nl }|.
    REPLACE ALL OCCURRENCES OF '## Recommendations ' IN rv_text WITH |## Recommendations{ lv_nl }|.
    REPLACE ALL OCCURRENCES OF '## Conclusion ' IN rv_text WITH |## Conclusion{ lv_nl }|.
    REPLACE ALL OCCURRENCES OF REGEX '\s+([0-9]+)\.\s+(\*\*)' IN rv_text WITH |{ lv_nl }$1. $2|.
    REPLACE ALL OCCURRENCES OF REGEX '\s+-\s+' IN rv_text WITH |{ lv_nl }- |.
  ENDMETHOD.

  METHOD render_abap_blocks.
    DATA lv_rest TYPE string.
    DATA lv_before TYPE string.
    DATA lv_code TYPE string.
    DATA lv_after TYPE string.
    DATA lv_start TYPE i.
    DATA lv_end TYPE i.
    DATA lv_code_start TYPE i.
    DATA lv_fence_len TYPE i.

    lv_rest = i_text.

    DO.
      FIND FIRST OCCURRENCE OF REGEX '```\s*[A-Za-z0-9_-]*\s*' IN lv_rest
        MATCH OFFSET lv_start
        MATCH LENGTH lv_fence_len.
      IF sy-subrc <> 0.
        EXIT.
      ENDIF.

      lv_before = substring( val = lv_rest len = lv_start ).
      lv_code_start = lv_start + lv_fence_len.
      lv_after = substring( val = lv_rest off = lv_code_start ).
      FIND FIRST OCCURRENCE OF '```' IN lv_after MATCH OFFSET lv_end.
      IF sy-subrc <> 0.
        EXIT.
      ENDIF.

      lv_code = substring( val = lv_after len = lv_end ).
      SHIFT lv_code LEFT DELETING LEADING cl_abap_char_utilities=>newline.
      rv_text = rv_text
             && render_markdown_text( lv_before )
             && code_block_to_html( lv_code ).
      lv_rest = substring( val = lv_after off = lv_end + 3 ).
    ENDDO.

    rv_text = rv_text && render_markdown_text( lv_rest ).
  ENDMETHOD.

  METHOD source_block_to_html.
    IF i_source IS INITIAL.
      RETURN.
    ENDIF.

    rv_html = cl_abap_char_utilities=>newline
           && |<div class="source_title">{ escape_html( i_title ) }</div>|
           && code_block_to_html( i_source ).
  ENDMETHOD.

  METHOD render_markdown_text.
    DATA lt_lines TYPE STANDARD TABLE OF string WITH NON-UNIQUE DEFAULT KEY.
    DATA lv_text TYPE string.
    DATA lv_hashes TYPE string.
    DATA lv_content TYPE string.
    DATA lv_marker TYPE string.
    DATA lv_item TYPE string.

    lv_text = normalize_markdown( i_text ).
    SPLIT lv_text AT cl_abap_char_utilities=>newline INTO TABLE lt_lines.

    LOOP AT lt_lines INTO DATA(lv_line).
      DATA(lv_trimmed) = lv_line.
      SHIFT lv_trimmed LEFT DELETING LEADING space.

      IF lv_trimmed IS INITIAL.
        rv_html = rv_html && cl_abap_char_utilities=>newline.
        CONTINUE.
      ENDIF.

      FIND FIRST OCCURRENCE OF REGEX '^(#{1,6})\s+(.+)$' IN lv_trimmed
        SUBMATCHES lv_hashes lv_content.
      IF sy-subrc = 0.
        rv_html = rv_html
               && |<div class="md_h">{ render_inline_markdown( lv_content ) }</div>|
               && cl_abap_char_utilities=>newline.
        CONTINUE.
      ENDIF.

      FIND FIRST OCCURRENCE OF REGEX '^([0-9]+\.)\s+(.+)$' IN lv_trimmed
        SUBMATCHES lv_marker lv_item.
      IF sy-subrc = 0.
        rv_html = rv_html
               && |<div class="md_li">{ escape_html( lv_marker ) } { render_inline_markdown( lv_item ) }</div>|
               && cl_abap_char_utilities=>newline.
        CONTINUE.
      ENDIF.

      FIND FIRST OCCURRENCE OF REGEX '^-\s+(.+)$' IN lv_trimmed
        SUBMATCHES lv_item.
      IF sy-subrc = 0.
        rv_html = rv_html
               && |<div class="md_li">- { render_inline_markdown( lv_item ) }</div>|
               && cl_abap_char_utilities=>newline.
        CONTINUE.
      ENDIF.

      FIND FIRST OCCURRENCE OF REGEX '^Tokens:' IN lv_trimmed.
      IF sy-subrc = 0.
        rv_html = rv_html
               && |<span class="tokens">{ render_inline_markdown( lv_trimmed ) }</span>|
               && cl_abap_char_utilities=>newline.
        CONTINUE.
      ENDIF.

      rv_html = rv_html
             && render_inline_markdown( lv_line )
             && cl_abap_char_utilities=>newline.
    ENDLOOP.
  ENDMETHOD.

  METHOD render_inline_markdown.
    rv_html = escape_html( i_text ).
    REPLACE ALL OCCURRENCES OF REGEX '\*\*([^*]+)\*\*' IN rv_html WITH '<strong>$1</strong>'.
    REPLACE ALL OCCURRENCES OF REGEX '`([^`]+)`' IN rv_html WITH '<code>$1</code>'.
  ENDMETHOD.

  METHOD code_block_to_html.
    DATA lt_lines TYPE STANDARD TABLE OF string WITH NON-UNIQUE DEFAULT KEY.
    DATA lv_lno TYPE i.

    SPLIT i_code AT cl_abap_char_utilities=>newline INTO TABLE lt_lines.
    rv_html = |<table class="code_tbl"><tbody>|.

    LOOP AT lt_lines INTO DATA(lv_line).
      lv_lno = lv_lno + 1.
      rv_html = rv_html
             && |<tr><td class="ln">{ lv_lno }</td>|
             && |<td class="cd">{ escape_html( i_text = lv_line ) }</td></tr>|.
    ENDLOOP.

    rv_html = rv_html && |</tbody></table>|.
  ENDMETHOD.

  METHOD escape_html.
    rv_text = i_text.
    REPLACE ALL OCCURRENCES OF '&' IN rv_text WITH '&amp;'.
    REPLACE ALL OCCURRENCES OF '<' IN rv_text WITH '&lt;'.
    REPLACE ALL OCCURRENCES OF '>' IN rv_text WITH '&gt;'.
    REPLACE ALL OCCURRENCES OF '"' IN rv_text WITH '&quot;'.
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
