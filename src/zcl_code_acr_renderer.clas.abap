CLASS zcl_code_acr_renderer DEFINITION
  PUBLIC
  FINAL
  CREATE PRIVATE.

  PUBLIC SECTION.
    CLASS-METHODS render_decline_thread_html
      IMPORTING
        iv_hunk_key      TYPE string
        it_hunk_threads  TYPE zif_code_acr_types=>ty_t_hunk_threads
        it_decline_notes TYPE zif_code_acr_types=>ty_t_decline_notes
        it_declined      TYPE zif_code_acr_types=>ty_approved
      RETURNING
        VALUE(result)    TYPE string.

    CLASS-METHODS render_hunk_actions_html
      IMPORTING
        iv_hunk_key      TYPE string
        it_approved      TYPE zif_code_acr_types=>ty_approved
        it_declined      TYPE zif_code_acr_types=>ty_approved
        it_hunk_actions  TYPE zif_code_acr_types=>ty_t_hunk_actions
        it_hunk_info     TYPE zif_code_acr_types=>ty_t_hunk_info
        it_hunk_threads  TYPE zif_code_acr_types=>ty_t_hunk_threads
        iv_ai_enabled    TYPE abap_bool DEFAULT abap_false
      RETURNING
        VALUE(result)    TYPE string.

    CLASS-METHODS render_comment_links
      IMPORTING
        iv_hunk_key      TYPE string
        it_hunk_threads  TYPE zif_code_acr_types=>ty_t_hunk_threads
        iv_ai_enabled    TYPE abap_bool DEFAULT abap_false
      RETURNING
        VALUE(result)    TYPE string.

    CLASS-METHODS render_hunk_action_meta
      IMPORTING
        iv_hunk_key      TYPE string
        iv_action        TYPE zif_code_acr_types=>ty_action_code
        it_hunk_actions  TYPE zif_code_acr_types=>ty_t_hunk_actions
      RETURNING
        VALUE(result)    TYPE string.

    CLASS-METHODS normalize_diff_html
      IMPORTING
        iv_html          TYPE string
        iv_two_pane      TYPE abap_bool
      RETURNING
        VALUE(result)    TYPE string.

    CLASS-METHODS render_blame_fallback
      IMPORTING
        is_hunk          TYPE zif_code_acr_types=>ty_hunk_info
        iv_html          TYPE string
        iv_blame         TYPE abap_bool
        iv_two_pane      TYPE abap_bool
      RETURNING
        VALUE(result)    TYPE string.

    CLASS-METHODS extract_blame_rows
      CHANGING
        cv_html          TYPE string
      RETURNING
        VALUE(result)    TYPE string.

    CLASS-METHODS render_hunk_comments_html
      IMPORTING
        iv_hunk_key      TYPE string
        it_hunk_threads  TYPE zif_code_acr_types=>ty_t_hunk_threads
      RETURNING
        VALUE(result)    TYPE string.

    CLASS-METHODS build_review_help_html
      RETURNING
        VALUE(result) TYPE string.

    CLASS-METHODS add_report_toolbar
      IMPORTING
        iv_html       TYPE string
        iv_enabled    TYPE abap_bool
      RETURNING
        VALUE(result) TYPE string.
protected section.
private section.
    CLASS-METHODS render_comment_action_link
      IMPORTING
        iv_event      TYPE string
        iv_hunk_key   TYPE string
        iv_text       TYPE string
        iv_background TYPE string
      RETURNING
        VALUE(result) TYPE string.
ENDCLASS.



CLASS ZCL_CODE_ACR_RENDERER IMPLEMENTATION.


  METHOD render_decline_thread_html.
    DATA(lv_comment_anchor) = |ai_comment_{ iv_hunk_key }|.
    REPLACE ALL OCCURRENCES OF '/' IN lv_comment_anchor WITH '_'.
    REPLACE ALL OCCURRENCES OF '~' IN lv_comment_anchor WITH '_'.
    REPLACE ALL OCCURRENCES OF ` ` IN lv_comment_anchor WITH `_`.

    READ TABLE it_hunk_threads INTO DATA(ls_thread)
      WITH TABLE KEY hunk_key = iv_hunk_key.
    IF sy-subrc <> 0.
      READ TABLE it_decline_notes INTO DATA(ls_note)
        WITH TABLE KEY hunk_key = iv_hunk_key.
      IF sy-subrc = 0 AND ls_note-note IS NOT INITIAL.
        DATA(lv_note_esc) = ls_note-note.
        REPLACE ALL OCCURRENCES OF `&` IN lv_note_esc WITH `&amp;`.
        REPLACE ALL OCCURRENCES OF `<` IN lv_note_esc WITH `&lt;`.
        REPLACE ALL OCCURRENCES OF `>` IN lv_note_esc WITH `&gt;`.
        REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>newline IN lv_note_esc WITH `<br>`.
        DATA(lv_note_bg) = COND string(
          WHEN line_exists( it_declined[ table_line = iv_hunk_key ] ) THEN `#fff1f4`
          ELSE `#f3f9ff` ).
        DATA(lv_note_border) = COND string(
          WHEN line_exists( it_declined[ table_line = iv_hunk_key ] ) THEN `#efb8c8`
          ELSE `#a8cde8` ).
        DATA(lv_note_text) = COND string(
          WHEN line_exists( it_declined[ table_line = iv_hunk_key ] ) THEN `#9f3b57`
          ELSE `#2874a6` ).
        result =
          |<tr id="{ lv_comment_anchor }"><td class="ln">&nbsp;</td><td class="cd" style="padding:6px 12px">| &&
          `<div style="display:inline-block;background:` && lv_note_bg &&
          `;border:1px solid ` && lv_note_border &&
          `;padding:5px 9px;color:` && lv_note_text &&
          `;font-size:11px;line-height:15px;font-style:italic;border-radius:6px">` &&
          lv_note_esc && `</div></td></tr>`.
      ENDIF.
      RETURN.
    ENDIF.

    DATA lv_msg_idx TYPE i.
    LOOP AT ls_thread-messages INTO DATA(ls_msg).
      lv_msg_idx = lv_msg_idx + 1.
      DATA(lv_row_id) = COND string(
        WHEN lv_msg_idx = lines( ls_thread-messages ) AND lv_comment_anchor IS NOT INITIAL
        THEN | id="{ lv_comment_anchor }"|
        ELSE `` ).
      DATA(lv_author_esc) = escape( val = CONV string( ls_msg-author ) format = cl_abap_format=>e_html_text ).
      DATA(lv_author_name_esc) = escape( val = CONV string( ls_msg-author_name ) format = cl_abap_format=>e_html_text ).
      DATA(lv_created_at_txt) = zcl_code_acr_state=>format_timestamp( ls_msg-created_at ).
      DATA(lv_text_esc) = escape( val = ls_msg-text format = cl_abap_format=>e_html_text ).
      REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>newline IN lv_text_esc WITH `<br>`.
      DATA(lv_note_bg_msg) = COND string(
        WHEN ls_msg-is_decline = abap_true THEN `#fff1f4`
        ELSE `#f3f9ff` ).
      DATA(lv_note_border_msg) = COND string(
        WHEN ls_msg-is_decline = abap_true THEN `#efb8c8`
        ELSE `#a8cde8` ).
      DATA(lv_note_text_msg) = COND string(
        WHEN ls_msg-is_decline = abap_true THEN `#9f3b57`
        ELSE `#2874a6` ).
      result = result &&
        `<tr` && lv_row_id && `><td class="ln">&nbsp;</td><td class="cd" style="padding:6px 12px">` &&
        `<div style="display:inline-block;margin:0 0 6px 0;background:` && lv_note_bg_msg &&
        `;border:1px solid ` && lv_note_border_msg && `;padding:6px 9px;max-width:900px;border-radius:6px">` &&
        `<div style="font-size:10px;color:#6f7f8f;font-weight:bold;margin-bottom:3px">` &&
        lv_author_esc && ` / ` && lv_author_name_esc &&
        ` <span style="font-weight:normal;color:#8a96a3">/ ` &&
        escape( val = lv_created_at_txt format = cl_abap_format=>e_html_text ) &&
        `</span></div>` &&
        `<div style="font-size:11px;line-height:15px;color:` && lv_note_text_msg &&
        `;font-style:italic">` &&
        lv_text_esc && `</div></div></td></tr>`.
    ENDLOOP.
  ENDMETHOD.


  METHOD render_hunk_actions_html.
    DATA(lv_status_html) = ``.
    DATA(lv_actions_html) = ``.
    DATA(lv_own_hunk) = zcl_code_acr_state=>is_own_hunk(
      iv_hunk_key  = iv_hunk_key
      it_hunk_info = it_hunk_info ).
    DATA(lv_global_action) = zcl_code_acr_state=>get_hunk_global_action(
      iv_hunk_key     = iv_hunk_key
      it_hunk_actions = it_hunk_actions ).

    IF line_exists( it_approved[ table_line = iv_hunk_key ] ).
      lv_status_html =
        `<span style="color:#27ae60;font-weight:bold">&#10003; approved</span>` &&
        render_hunk_action_meta(
          iv_hunk_key     = iv_hunk_key
          iv_action       = 'A'
          it_hunk_actions = it_hunk_actions ).
      IF lv_own_hunk = abap_true.
        lv_actions_html = render_comment_links(
          iv_hunk_key     = iv_hunk_key
          it_hunk_threads = it_hunk_threads
          iv_ai_enabled   = iv_ai_enabled ).
      ELSE.
        lv_actions_html =
          |<a href="sapevent:undo~{ iv_hunk_key }"| &&
          ` style="margin-left:8px;background:#95a5a6;color:#fff;font-weight:bold;` &&
          `text-decoration:none;font-size:11px;border-radius:3px;padding:2px 7px">Undo</a>` &&
          render_comment_links(
            iv_hunk_key     = iv_hunk_key
            it_hunk_threads = it_hunk_threads
            iv_ai_enabled   = iv_ai_enabled ).
      ENDIF.
    ELSEIF line_exists( it_declined[ table_line = iv_hunk_key ] ).
      lv_status_html =
        `<span style="color:#e74c3c;font-weight:bold">&#10007; declined</span>` &&
        render_hunk_action_meta(
          iv_hunk_key     = iv_hunk_key
          iv_action       = 'D'
          it_hunk_actions = it_hunk_actions ).
      IF lv_own_hunk = abap_true.
        lv_actions_html = render_comment_links(
          iv_hunk_key     = iv_hunk_key
          it_hunk_threads = it_hunk_threads
          iv_ai_enabled   = iv_ai_enabled ).
      ELSE.
        lv_actions_html =
          |<a href="sapevent:undo~{ iv_hunk_key }"| &&
          ` style="margin-left:8px;background:#95a5a6;color:#fff;font-weight:bold;` &&
          `text-decoration:none;font-size:11px;border-radius:3px;padding:2px 7px">Undo</a>` &&
          |<a href="sapevent:approve~{ iv_hunk_key }"| &&
          ` style="margin-left:4px;background:#27ae60;color:#fff;font-weight:bold;` &&
          `text-decoration:none;font-size:11px;border-radius:3px;padding:2px 7px">&#10003; Approve</a>` &&
          render_comment_links(
            iv_hunk_key     = iv_hunk_key
            it_hunk_threads = it_hunk_threads
            iv_ai_enabled   = iv_ai_enabled ).
      ENDIF.
    ELSEIF lv_global_action = 'A' OR lv_global_action = 'D'.
      lv_status_html = COND string(
        WHEN lv_global_action = 'A'
        THEN `<span style="color:#27ae60;font-weight:bold">&#10003; approved</span>` &&
             render_hunk_action_meta(
               iv_hunk_key     = iv_hunk_key
               iv_action       = 'A'
               it_hunk_actions = it_hunk_actions )
        ELSE `<span style="color:#e74c3c;font-weight:bold">&#10007; declined</span>` &&
             render_hunk_action_meta(
               iv_hunk_key     = iv_hunk_key
               iv_action       = 'D'
               it_hunk_actions = it_hunk_actions ) ).
      IF lv_own_hunk = abap_true.
        lv_actions_html = render_comment_links(
          iv_hunk_key     = iv_hunk_key
          it_hunk_threads = it_hunk_threads
          iv_ai_enabled   = iv_ai_enabled ).
      ELSE.
        lv_actions_html =
          |<a href="sapevent:approve~{ iv_hunk_key }"| &&
          ` style="margin-left:8px;background:#27ae60;color:#fff;font-weight:bold;` &&
          `text-decoration:none;font-size:11px;border-radius:3px;padding:2px 7px">&#10003; Approve</a>` &&
          |<a href="sapevent:decline~{ iv_hunk_key }"| &&
          ` style="margin-left:4px;background:#922b21;color:#fff;font-weight:bold;` &&
          `text-decoration:none;font-size:11px;border-radius:3px;padding:2px 7px">&#10007; Decline</a>` &&
          render_comment_links(
            iv_hunk_key     = iv_hunk_key
            it_hunk_threads = it_hunk_threads
            iv_ai_enabled   = iv_ai_enabled ).
      ENDIF.
    ELSE.
      IF lv_own_hunk = abap_true.
        lv_status_html =
          `<span style="color:#7f8c8d;font-weight:bold">&#9675; own block</span>`.
        lv_actions_html = render_comment_links(
          iv_hunk_key     = iv_hunk_key
          it_hunk_threads = it_hunk_threads
          iv_ai_enabled   = iv_ai_enabled ).
      ELSE.
        lv_status_html =
          `<span style="color:#7f8c8d;font-weight:bold">&#9675; open</span>`.
        lv_actions_html =
          |<a href="sapevent:approve~{ iv_hunk_key }"| &&
          ` style="margin-left:8px;background:#27ae60;color:#fff;font-weight:bold;` &&
          `text-decoration:none;font-size:11px;border-radius:3px;padding:2px 7px">&#10003; Approve</a>` &&
          |<a href="sapevent:decline~{ iv_hunk_key }"| &&
          ` style="margin-left:4px;background:#922b21;color:#fff;font-weight:bold;` &&
          `text-decoration:none;font-size:11px;border-radius:3px;padding:2px 7px">&#10007; Decline</a>` &&
          render_comment_links(
            iv_hunk_key     = iv_hunk_key
            it_hunk_threads = it_hunk_threads
            iv_ai_enabled   = iv_ai_enabled ).
      ENDIF.
    ENDIF.

    result =
      `<div style="display:flex;align-items:center;gap:0;margin:2px 0 8px 0">` &&
      lv_status_html && lv_actions_html && `</div>`.
  ENDMETHOD.


  METHOD render_comment_links.
    DATA(lv_last_note) = zcl_code_acr_state=>get_last_own_comment(
      iv_hunk_key     = iv_hunk_key
      it_hunk_threads = it_hunk_threads ).
    IF lv_last_note IS NOT INITIAL.
      result = render_comment_action_link(
        iv_event      = `editreview`
        iv_hunk_key   = iv_hunk_key
        iv_text       = `Edit`
        iv_background = `#7f8c8d` ).
    ENDIF.

    result = result &&
      render_comment_action_link(
        iv_event      = `addcomment`
        iv_hunk_key   = iv_hunk_key
        iv_text       = `Add Comment`
        iv_background = `#3498db` ).

    IF iv_ai_enabled = abap_true.
      result = result &&
        render_comment_action_link(
          iv_event      = `askai`
          iv_hunk_key   = iv_hunk_key
          iv_text       = `ASK AI`
          iv_background = `#8e44ad` ).
    ENDIF.
  ENDMETHOD.


  METHOD render_comment_action_link.
    result =
      |<a href="sapevent:{ iv_event }~{ iv_hunk_key }"| &&
      ` onclick="if(window._saveScroll)window._saveScroll()"` &&
      ` style="margin-left:4px;background:` && iv_background &&
      `;color:#fff;font-weight:bold;text-decoration:none;font-style:normal;` &&
      `font-size:11px;border-radius:3px;padding:2px 7px">` &&
      escape( val = iv_text format = cl_abap_format=>e_html_text ) &&
      `</a>`.
  ENDMETHOD.


  METHOD render_hunk_action_meta.
    DATA ls_action TYPE zif_code_acr_types=>ty_hunk_action.
    LOOP AT it_hunk_actions INTO DATA(ls_action_cur)
      WHERE hunk_key = iv_hunk_key AND action = iv_action.
      IF ls_action IS INITIAL OR ls_action_cur-changed_at > ls_action-changed_at.
        ls_action = ls_action_cur.
      ENDIF.
    ENDLOOP.
    CHECK ls_action IS NOT INITIAL.
    DATA(lv_label) = COND string(
      WHEN iv_action = 'A' THEN ''
      WHEN iv_action = 'D' THEN ''
      ELSE ` reviewed` ).
    result =
      | <span style="font-weight:normal;color:#7f8c8d;font-size:10px">| &&
      |{ lv_label }/ by { escape( val = CONV string( ls_action-reviewer ) format = cl_abap_format=>e_html_text ) }| &&
      | / { escape( val = CONV string( ls_action-reviewer_name ) format = cl_abap_format=>e_html_text ) }| &&
      | / { escape( val = zcl_code_acr_state=>format_timestamp( ls_action-changed_at ) format = cl_abap_format=>e_html_text ) }</span>|.
  ENDMETHOD.


  METHOD normalize_diff_html.
    result = iv_html.
    CHECK iv_two_pane = abap_false.
    CHECK result CS `<td class="sep"></td>`.

    DATA(lv_rows_html) = result.
    DATA(lv_norm_html) = ``.
    DATA lv_row_start TYPE i.
    DATA lv_row_close_rel TYPE i.
    DATA lv_row_close TYPE i.
    DATA lv_row_len TYPE i.
    DATA lv_row_html TYPE string.
    DATA lv_gt_pos TYPE i.
    DATA lv_sep_pos TYPE i.
    DATA lv_body_left TYPE string.
    DATA lv_body_right TYPE string.
    DATA lv_plain_left TYPE string.
    DATA lv_plain_right TYPE string.

    WHILE lv_rows_html CS `<tr`.
      lv_row_start = sy-fdpos.
      IF lv_row_start > 0.
        lv_norm_html = lv_norm_html && lv_rows_html(lv_row_start).
        lv_rows_html = lv_rows_html+lv_row_start.
      ENDIF.

      FIND FIRST OCCURRENCE OF `</tr>` IN lv_rows_html MATCH OFFSET lv_row_close_rel.
      IF sy-subrc <> 0.
        lv_norm_html = lv_norm_html && lv_rows_html.
        CLEAR lv_rows_html.
        EXIT.
      ENDIF.

      lv_row_close = lv_row_close_rel + 5.
      lv_row_html = lv_rows_html(lv_row_close).
      lv_rows_html = lv_rows_html+lv_row_close.
      IF lv_row_html CS `<td class="sep"></td>`.
        FIND FIRST OCCURRENCE OF `>` IN lv_row_html MATCH OFFSET lv_gt_pos.
        FIND FIRST OCCURRENCE OF `<td class="sep"></td>` IN lv_row_html MATCH OFFSET lv_sep_pos.
        IF sy-subrc = 0 AND lv_gt_pos >= 0 AND lv_sep_pos > lv_gt_pos.
          DATA(lv_body_left_off) = lv_gt_pos + 1.
          DATA(lv_body_left_len) = lv_sep_pos - lv_gt_pos - 1.
          DATA(lv_body_right_off) = lv_sep_pos + 21.
          DATA(lv_row_prefix_len) = lv_gt_pos + 1.
          lv_body_left = lv_row_html+lv_body_left_off(lv_body_left_len).
          lv_body_right = lv_row_html+lv_body_right_off.
          lv_row_len = strlen( lv_body_right ).
          IF lv_row_len >= 5.
            DATA(lv_body_right_len) = lv_row_len - 5.
            lv_body_right = lv_body_right(lv_body_right_len).
          ENDIF.
          lv_plain_left = lv_body_left.
          lv_plain_right = lv_body_right.
          REPLACE FIRST OCCURRENCE OF REGEX `<td class="ln"[^>]*>[^<]*</td>` IN lv_plain_left WITH ``.
          REPLACE FIRST OCCURRENCE OF REGEX `<td class="ln"[^>]*>[^<]*</td>` IN lv_plain_right WITH ``.
          REPLACE ALL OCCURRENCES OF REGEX `<[^>]+>` IN lv_plain_left WITH ``.
          REPLACE ALL OCCURRENCES OF REGEX `<[^>]+>` IN lv_plain_right WITH ``.
          CONDENSE lv_plain_left NO-GAPS.
          CONDENSE lv_plain_right NO-GAPS.
          IF lv_plain_left IS NOT INITIAL
             AND lv_plain_right IS NOT INITIAL
             AND lv_plain_left <> lv_plain_right
             AND ( lv_row_html NS `<span style=` OR lv_row_html CS `data-split="x"` ).
            lv_norm_html = lv_norm_html &&
              lv_row_html(lv_row_prefix_len) && lv_body_right && `</tr>` &&
              lv_row_html(lv_row_prefix_len) && lv_body_left && `</tr>`.
          ELSE.
            lv_norm_html = lv_norm_html &&
              lv_row_html(lv_row_prefix_len) &&
              COND string(
                WHEN strlen( lv_plain_right ) >= strlen( lv_plain_left )
                THEN lv_body_right ELSE lv_body_left ) &&
              `</tr>`.
          ENDIF.
        ELSE.
          lv_norm_html = lv_norm_html && lv_row_html.
        ENDIF.
      ELSE.
        lv_norm_html = lv_norm_html && lv_row_html.
      ENDIF.
    ENDWHILE.

    result = lv_norm_html && lv_rows_html.
  ENDMETHOD.


  METHOD render_blame_fallback.
    CHECK iv_blame = abap_true.
    CHECK is_hunk-author IS NOT INITIAL.
    CHECK iv_html NS `background:#e8f4e8`.
    CHECK iv_html NS `background:#fdf0f0`.

    DATA(lv_author) =
      `<b style="color:#0066aa">` &&
      escape( val = CONV string( is_hunk-author ) format = cl_abap_format=>e_html_text ) &&
      COND string(
        WHEN is_hunk-author_name IS NOT INITIAL
        THEN | ({ escape( val = CONV string( is_hunk-author_name ) format = cl_abap_format=>e_html_text ) })|
        ELSE `` ) &&
      `</b>`.
    DATA(lv_verb) = SWITCH string(
      is_hunk-change_kind
      WHEN `added` THEN `inserted`
      WHEN `deleted` THEN `deleted`
      ELSE `changed` ).
    DATA(lv_versno) = COND string(
      WHEN is_hunk-versno_new_text IS NOT INITIAL THEN is_hunk-versno_new_text
      WHEN is_hunk-versno_new IS NOT INITIAL THEN CONV string( is_hunk-versno_new )
      ELSE `` ).
    DATA(lv_version_html) = COND string(
      WHEN lv_versno IS NOT INITIAL
      THEN | v.{ escape( val = lv_versno format = cl_abap_format=>e_html_text ) }|
      ELSE `` ).
    DATA(lv_line) = |-- { lv_author } { lv_verb }{ lv_version_html } --|.

    IF iv_two_pane = abap_true.
      result =
        |<tr style="background:#e8f4e8;color:#555;font-size:10px;font-style:italic">| &&
        |<td class="ln">&gt;</td><td class="cd" colspan="3">{ lv_line }</td>| &&
        |<td class="ln"></td><td class="cd"></td></tr>|.
    ELSE.
      result =
        |<tr style="background:#e8f4e8;color:#555;font-size:10px;font-style:italic">| &&
        |<td class="ln">&gt;</td><td class="cd">{ lv_line }</td></tr>|.
    ENDIF.
  ENDMETHOD.


  METHOD extract_blame_rows.
    DATA(lv_rest) = cv_html.
    DATA(lv_clean) = ``.
    CLEAR result.

    WHILE lv_rest CS `<tr`.
      DATA(lv_row_start) = sy-fdpos.
      IF lv_row_start > 0.
        lv_clean = lv_clean && lv_rest(lv_row_start).
        lv_rest = lv_rest+lv_row_start.
      ENDIF.

      FIND FIRST OCCURRENCE OF `</tr>` IN lv_rest MATCH OFFSET DATA(lv_row_close_rel).
      IF sy-subrc <> 0.
        lv_clean = lv_clean && lv_rest.
        CLEAR lv_rest.
        EXIT.
      ENDIF.

      DATA(lv_row_len) = lv_row_close_rel + 5.
      DATA(lv_row_html) = lv_rest(lv_row_len).
      lv_rest = lv_rest+lv_row_len.
      IF lv_row_html CS `background:#e8f4e8`
         OR lv_row_html CS `background:#fdf0f0`.
        result = result && lv_row_html.
      ELSE.
        lv_clean = lv_clean && lv_row_html.
      ENDIF.
    ENDWHILE.

    cv_html = lv_clean && lv_rest.
  ENDMETHOD.


  METHOD render_hunk_comments_html.
    READ TABLE it_hunk_threads INTO DATA(ls_thread)
      WITH TABLE KEY hunk_key = iv_hunk_key.
    CHECK sy-subrc = 0.
    CHECK ls_thread-messages IS NOT INITIAL.

    DATA(lv_comments_html) = ``.
    LOOP AT ls_thread-messages INTO DATA(ls_msg).
      CHECK ls_msg-text IS NOT INITIAL.
      DATA(lv_note_esc) = escape( val = ls_msg-text format = cl_abap_format=>e_html_text ).
      REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>newline IN lv_note_esc WITH `<br>`.
      DATA(lv_created_at_txt) = zcl_code_acr_state=>format_timestamp( ls_msg-created_at ).
      DATA(lv_note_style) = COND string(
        WHEN ls_msg-is_decline = abap_true
        THEN ` style="background:#fff1f4;border-color:#efb8c8;color:#9f3b57"`
        ELSE `` ).
      lv_comments_html = lv_comments_html &&
        |<span class="meta">{ escape( val = CONV string( ls_msg-author ) format = cl_abap_format=>e_html_text ) }| &&
        | / { escape( val = CONV string( ls_msg-author_name ) format = cl_abap_format=>e_html_text ) }| &&
        | / { escape( val = lv_created_at_txt format = cl_abap_format=>e_html_text ) }</span>| &&
        |<div class="note"{ lv_note_style }>{ lv_note_esc }</div>|.
    ENDLOOP.

    CHECK lv_comments_html IS NOT INITIAL.
    result =
      |<div id="{ zcl_code_acr_ai=>get_hunk_scroll_anchor( iv_hunk_key ) }" class="comments">{ lv_comments_html }</div>|.
  ENDMETHOD.


  METHOD build_review_help_html.
    result =
      `<!DOCTYPE html><html><head><meta charset="utf-8"><style>` &&
      `body{font:13px/1.5 Segoe UI,Arial,sans-serif;background:#f7f7f9;color:#222;padding:18px;}` &&
      `h2{margin:0 0 10px;color:#0a6ed1;}p{margin:0 0 12px;}` &&
      `table{border-collapse:collapse;width:100%;background:#fff;margin:10px 0 14px;}` &&
      `th,td{border:1px solid #d9d9d9;padding:7px 9px;text-align:left;vertical-align:top;}` &&
      `th{background:#eef4fb;}code{background:#eef2f7;padding:1px 4px;border-radius:3px;}` &&
      `ol{margin:8px 0 0 22px;padding:0;}li{margin:0 0 6px;}` &&
      `</style></head><body>` &&
      `<h2>Save review requires table ZAVE_REVIEW</h2>` &&
      `<p>The button can save review data only after a transparent table <code>ZAVE_REVIEW</code> is created and activated.</p>` &&
      `<p>For now keep the design minimal: one row per transport request, and the full review with save history stored inside one JSON payload.</p>` &&
      `<table><tr><th>Field</th><th>Type</th><th>Purpose</th></tr>` &&
      `<tr><td>MANDT</td><td>MANDT</td><td>Client field</td></tr>` &&
      `<tr><td>TRKORR</td><td>TRKORR</td><td>Transport request key</td></tr>` &&
      `<tr><td>PAYLOAD</td><td>STRING</td><td>Stored review JSON including current state and save history</td></tr>` &&
      `</table>` &&
      `<ol>` &&
      `<li>Create transparent table <code>ZAVE_REVIEW</code>.</li>` &&
      `<li>Make <code>MANDT</code> and <code>TRKORR</code> key fields.</li>` &&
      `<li>Add field <code>PAYLOAD</code> as type <code>STRING</code>.</li>` &&
      `<li>Activate the table. No ZIP or compression is needed yet.</li>` &&
      `<li>Return to AVE and press <code>Save</code> again.</li>` &&
      `</ol>` &&
      `</body></html>`.
  ENDMETHOD.


  METHOD add_report_toolbar.
    result = iv_html.
    CHECK iv_enabled = abap_true.
    CHECK result CS `</body>`.

    DATA(lv_toolbar) =
      `<div style="position:fixed;top:8px;right:12px;z-index:1000">` &&
      `<a href="sapevent:recalcpick~0"` &&
      ` style="display:inline-block;background:#7f8c8d;color:#fff;` &&
      `padding:5px 14px;border-radius:4px;font:bold 12px Consolas,sans-serif;` &&
      `text-decoration:none;box-shadow:0 1px 4px rgba(0,0,0,.25)">Recalc Diff</a>` &&
      `</div>`.

    result = replace( val = result sub = `</body>` with = lv_toolbar && `</body>` ).
  ENDMETHOD.
ENDCLASS.
