class ZCL_API_HISTORY_POPUP definition
  public
  create public .

public section.

  methods CONSTRUCTOR
    importing
      !IT_MESSAGES type ZCL_AI_MESSAGES=>TT_MESSAGES .
  methods REFRESH
    importing
      !IT_MESSAGES type ZCL_AI_MESSAGES=>TT_MESSAGES .
  methods SHOW .
protected section.
private section.

  types:
    ty_textedit_line(255) TYPE c .
  types:
    tt_textedit_lines     TYPE TABLE OF ty_textedit_line .
  types:
    tt_html               TYPE STANDARD TABLE OF w3html WITH NON-UNIQUE DEFAULT KEY .
  types:
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
             duration_seconds TYPE string,
             request_preview TYPE string,
             answer_preview TYPE string,
             request        TYPE string,
             answer         TYPE string,
             rowcolor(4)    TYPE c,
            END OF ty_history_row .
  types:
    tt_history_rows TYPE STANDARD TABLE OF ty_history_row WITH NON-UNIQUE DEFAULT KEY .

  data MO_DIALOG type ref to CL_GUI_DIALOGBOX_CONTAINER .
  data MO_SPLIT type ref to CL_GUI_SPLITTER_CONTAINER .
  data MO_DETAILS type ref to CL_GUI_SPLITTER_CONTAINER .
  data MO_REQUEST type ref to CL_GUI_HTML_VIEWER .
  data MO_ANSWER type ref to CL_GUI_HTML_VIEWER .
  data MO_ALV type ref to CL_GUI_ALV_GRID .
  data MT_HISTORY type TT_HISTORY_ROWS .
  data MT_MESSAGES type ZCL_AI_MESSAGES=>TT_MESSAGES .

  methods BUILD_HISTORY .
  methods CREATE_ALV
    importing
      !IO_PARENT type ref to CL_GUI_CONTAINER .
  methods EXTRACT_USAGE
    importing
      !I_TEXT type STRING
    changing
      !CS_ROW type TY_HISTORY_ROW .
  methods ON_DIALOG_CLOSE
    for event CLOSE of CL_GUI_DIALOGBOX_CONTAINER .
  methods ON_DOUBLE_CLICK
    for event DOUBLE_CLICK of CL_GUI_ALV_GRID
    importing
      !ES_ROW_NO
      !E_COLUMN .
  methods SHOW_ROW
    importing
      !I_ROW type I .
  methods DISPLAY_TEXT
    importing
      !IO_VIEWER type ref to CL_GUI_HTML_VIEWER
      !I_TEXT type STRING .
  methods SOURCE_TEXT_TO_HTML
    importing
      !I_TEXT type STRING
    returning
      value(RV_HTML) type STRING .
  methods ESCAPE_HTML
    importing
      !I_TEXT type STRING
    returning
      value(RV_TEXT) type STRING .
  methods PREVIEW
    importing
      !I_TEXT type STRING
    returning
      value(RV_TEXT) type STRING .
ENDCLASS.



CLASS ZCL_API_HISTORY_POPUP IMPLEMENTATION.


  method BUILD_HISTORY.

    CLEAR mt_history.

    DATA ls_row TYPE ty_history_row.
    DATA lv_request TYPE string.
    DATA lv_request_type TYPE string.
    DATA lv_request_agent TYPE string.
    DATA lv_request_session TYPE i.
    DATA lv_request_message_id TYPE i.
    DATA lv_has_request TYPE abap_bool.

    DATA lv_system_content TYPE string.  " accumulated system prompt for next user msg

    LOOP AT mt_messages INTO DATA(ls_message).
      IF ls_message-role = 'system'.
        " System prompt - buffer it; will be shown together with next user message
        lv_system_content = ls_message-content.
        lv_request_agent   = ls_message-agent.
        lv_request_session = ls_message-session_id.
        CONTINUE.

      ELSEIF ls_message-role = 'user'.
        IF lv_has_request = abap_true.
          CLEAR ls_row.
          ls_row-session_id = lv_request_session.
          ls_row-owner = lv_request_agent.
          ls_row-request_type = lv_request_type.
          ls_row-request = lv_request.
          ls_row-request_preview = preview( ls_row-request ).
          CLEAR ls_row-seq.
          LOOP AT mt_history TRANSPORTING NO FIELDS
            WHERE session_id = ls_row-session_id.
            ls_row-seq = ls_row-seq + 1.
          ENDLOOP.
          ls_row-seq = ls_row-seq + 1.
          APPEND ls_row TO mt_history.
        ENDIF.

        " Prepend system prompt block if present
        IF lv_system_content IS NOT INITIAL.
          lv_request = |=== SYSTEM ===| && cl_abap_char_utilities=>newline
                    && lv_system_content && cl_abap_char_utilities=>newline
                    && cl_abap_char_utilities=>newline
                    && |=== USER ===| && cl_abap_char_utilities=>newline
                    && ls_message-content.
          CLEAR lv_system_content.
        ELSE.
          lv_request = ls_message-content.
        ENDIF.

        CASE ls_message-prompt_type.
          WHEN 'USER_PROMPT'. lv_request_type = 'USER'.
          WHEN 'AGENT_PROMPT'.  lv_request_type = 'AGENT'.
          WHEN 'COMMAND'.       lv_request_type = 'COMMAND'.
          WHEN OTHERS.          lv_request_type = ls_message-prompt_type.
        ENDCASE.
        lv_request_agent = ls_message-agent.
        lv_request_session = ls_message-session_id.
        lv_request_message_id = ls_message-message_id.
        lv_has_request = abap_true.
      ELSE.
        CLEAR ls_row.
        ls_row-session_id = ls_message-session_id.
        ls_row-owner = ls_message-agent.
        ls_row-request_type = lv_request_type.
        CASE ls_message-prompt_type.
          WHEN 'LLM_RESPONSE' OR 'FINAL_ANSWER'. ls_row-answer_type = 'LLM'.
          WHEN 'AGENT_RESPONSE'.                 ls_row-answer_type = 'ABAP'.
          WHEN OTHERS.                           ls_row-answer_type = ls_message-prompt_type.
        ENDCASE.
        ls_row-duration_seconds = ls_message-duration_seconds.
        ls_row-request = lv_request.
        ls_row-answer = ls_message-content.
        IF ls_row-owner IS INITIAL.
          ls_row-owner = lv_request_agent.
        ENDIF.
        IF ls_row-session_id IS INITIAL.
          ls_row-session_id = lv_request_session.
        ENDIF.
        IF ls_message-tok_in > 0 OR ls_message-tok_out > 0.
          ls_row-prompt_tokens     = CONV string( ls_message-tok_in ).
          ls_row-completion_tokens = CONV string( ls_message-tok_out ).
          ls_row-total_tokens      = CONV string( ls_message-tok_in + ls_message-tok_out ).
        ENDIF.
        DATA(lv_answer_upper) = ls_row-answer.
        TRANSLATE lv_answer_upper TO UPPER CASE.
        DATA(lv_answer_key) = lv_answer_upper.
        CONDENSE lv_answer_key.

        IF ls_row-owner = zcl_ai_agents_prompts=>c_agent_code_reader
        AND ls_row-answer_type = 'ABAP'
        AND (    lv_answer_key CP 'SOURCE FOR PROGRAM * WAS NOT FOUND*'
              OR lv_answer_key CP 'SOURCE FOR PROGRAM * CANNOT BE READ*'
              OR lv_answer_key CP 'CLASS * WAS NOT FOUND*'
              OR lv_answer_key CP 'METHOD * WAS NOT FOUND*'
              OR lv_answer_key CP 'METHOD COMMAND IS INCOMPLETE*'
              OR lv_answer_key CP 'NO CODE CONTEXT WAS RESOLVED*' ).
          ls_row-rowcolor = 'C601'. " red text
        ELSEIF ls_row-owner <> zcl_ai_agents_prompts=>c_agent_code_reader
        AND lv_answer_upper CS 'ERROR:'.
          ls_row-rowcolor = 'C601'. " red text
        ELSEIF ls_row-prompt_tokens IS NOT INITIAL
            OR ls_row-total_tokens IS NOT INITIAL
            OR ls_row-answer_type = 'LLM'.
          ls_row-rowcolor = 'C110'. " blue
        ENDIF.
        ls_row-request_preview = preview( ls_row-request ).
        ls_row-answer_preview = preview( ls_row-answer ).
        CLEAR ls_row-seq.
        LOOP AT mt_history TRANSPORTING NO FIELDS
          WHERE session_id = ls_row-session_id.
          ls_row-seq = ls_row-seq + 1.
        ENDLOOP.
        ls_row-seq = ls_row-seq + 1.
        APPEND ls_row TO mt_history.
        CLEAR: lv_request, lv_request_type, lv_request_agent, lv_request_session, lv_request_message_id.
        lv_has_request = abap_false.
      ENDIF.
    ENDLOOP.

    IF lv_has_request = abap_true.
      CLEAR ls_row.
      ls_row-session_id = lv_request_session.
      ls_row-owner = lv_request_agent.
      ls_row-request_type = lv_request_type.
      ls_row-request = lv_request.
      ls_row-request_preview = preview( ls_row-request ).
      CLEAR ls_row-seq.
      LOOP AT mt_history TRANSPORTING NO FIELDS
        WHERE session_id = ls_row-session_id.
        ls_row-seq = ls_row-seq + 1.
      ENDLOOP.
      ls_row-seq = ls_row-seq + 1.
      APPEND ls_row TO mt_history.
    ENDIF.

  endmethod.


  method CONSTRUCTOR.

    mt_messages = it_messages.

  endmethod.


  METHOD refresh.

    mt_messages = it_messages.
    build_history( ).

    IF mo_alv IS BOUND.
      mo_alv->refresh_table_display(
        EXCEPTIONS
          finished = 1
          OTHERS   = 2 ).
      IF sy-subrc <> 0.
        CLEAR: mo_alv,
               mo_request,
               mo_answer,
               mo_details,
               mo_split,
               mo_dialog.
        RETURN.
      ENDIF.
    ENDIF.

    IF mt_history IS NOT INITIAL
    AND mo_request IS BOUND
    AND mo_answer IS BOUND.
      show_row( lines( mt_history ) ).
    ENDIF.

    CALL METHOD cl_gui_cfw=>flush
      EXCEPTIONS
        cntl_system_error = 1
        cntl_error        = 2
        OTHERS            = 3.
    IF sy-subrc <> 0.
      CLEAR: mo_alv,
             mo_request,
             mo_answer,
             mo_details,
             mo_split,
             mo_dialog.
    ENDIF.

  ENDMETHOD.


  method CREATE_ALV.

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
    CLEAR ls_fc. ls_fc-fieldname = 'DURATION_SECONDS'. ls_fc-coltext = 'Sec'.
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

  endmethod.


  method DISPLAY_TEXT.

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
             && |.log\{font-family:Consolas,"Courier New",monospace;line-height:1.3;white-space:pre;overflow-x:auto;\}|
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

  endmethod.


  method ESCAPE_HTML.

    rv_text = i_text.
    REPLACE ALL OCCURRENCES OF '&' IN rv_text WITH '&amp;'.
    REPLACE ALL OCCURRENCES OF '<' IN rv_text WITH '&lt;'.
    REPLACE ALL OCCURRENCES OF '>' IN rv_text WITH '&gt;'.
    REPLACE ALL OCCURRENCES OF '"' IN rv_text WITH '&quot;'.

  endmethod.


  method EXTRACT_USAGE.

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

  endmethod.


  method ON_DIALOG_CLOSE.

    IF mo_dialog IS BOUND.
      mo_dialog->free(
        EXCEPTIONS
          cntl_error        = 1
          cntl_system_error = 2
          OTHERS            = 3 ).
    ENDIF.

    CALL METHOD cl_gui_cfw=>flush
      EXCEPTIONS
        cntl_system_error = 1
        cntl_error        = 2
        OTHERS            = 3.

    CLEAR: mo_alv,
           mo_request,
           mo_answer,
           mo_details,
           mo_split,
           mo_dialog.

  endmethod.


  method ON_DOUBLE_CLICK.

    show_row( es_row_no-row_id ).

  endmethod.


  method PREVIEW.

    rv_text = i_text.
    REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>newline IN rv_text WITH space.
    CONDENSE rv_text.

    IF strlen( rv_text ) > 120.
      rv_text = rv_text(120).
    ENDIF.

  endmethod.


  method SHOW.

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

    mo_split->set_row_height( id = 1 height = 60 ).
    mo_split->set_row_height( id = 2 height = 40 ).

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

  endmethod.


  method SHOW_ROW.

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

  endmethod.


  method SOURCE_TEXT_TO_HTML.

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

  endmethod.
ENDCLASS.
