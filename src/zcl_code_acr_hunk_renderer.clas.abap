CLASS zcl_code_acr_hunk_renderer DEFINITION
  PUBLIC
  FINAL
  CREATE PRIVATE.

  PUBLIC SECTION.
    CLASS-METHODS inject_approve_btn
      IMPORTING
        iv_key           TYPE string
        it_hunk_info     TYPE zif_code_acr_types=>ty_t_hunk_info
        it_approved      TYPE zif_code_acr_types=>ty_approved
        it_declined      TYPE zif_code_acr_types=>ty_approved
        it_decline_notes TYPE zif_code_acr_types=>ty_t_decline_notes
        it_hunk_actions  TYPE zif_code_acr_types=>ty_t_hunk_actions
        it_hunk_threads  TYPE zif_code_acr_types=>ty_t_hunk_threads
        iv_ai_enabled    TYPE abap_bool DEFAULT abap_false
      CHANGING
        cv_html          TYPE string
        ct_acr_stats     TYPE zif_code_acr_types=>ty_t_obj_stats.

    CLASS-METHODS acr_approve_cell
      IMPORTING
        iv_key           TYPE string
        it_hunk_info     TYPE zif_code_acr_types=>ty_t_hunk_info
        it_approved      TYPE zif_code_acr_types=>ty_approved
        it_declined      TYPE zif_code_acr_types=>ty_approved
        it_hunk_actions  TYPE zif_code_acr_types=>ty_t_hunk_actions
        it_hunk_threads  TYPE zif_code_acr_types=>ty_t_hunk_threads
        iv_ai_enabled    TYPE abap_bool DEFAULT abap_false
      RETURNING
        VALUE(result)    TYPE string.

    CLASS-METHODS acr_approve_fixed
      IMPORTING
        iv_key           TYPE string
        it_hunk_info     TYPE zif_code_acr_types=>ty_t_hunk_info
        it_approved      TYPE zif_code_acr_types=>ty_approved
        it_declined      TYPE zif_code_acr_types=>ty_approved
        it_hunk_actions  TYPE zif_code_acr_types=>ty_t_hunk_actions
        it_hunk_threads  TYPE zif_code_acr_types=>ty_t_hunk_threads
        iv_ai_enabled    TYPE abap_bool DEFAULT abap_false
      RETURNING
        VALUE(result)    TYPE string.

    CLASS-METHODS build_approveall_btn
      IMPORTING
        iv_obj_key       TYPE string
        iv_total_hunks   TYPE i
        it_approved      TYPE zif_code_acr_types=>ty_approved
        it_declined      TYPE zif_code_acr_types=>ty_approved
        it_hunk_actions  TYPE zif_code_acr_types=>ty_t_hunk_actions
      RETURNING
        VALUE(result)    TYPE string.
ENDCLASS.


CLASS zcl_code_acr_hunk_renderer IMPLEMENTATION.

  METHOD inject_approve_btn.
    DATA(result) = cv_html.

    DATA lt_bm TYPE match_result_tab.
    FIND ALL OCCURRENCES OF REGEX `<!--ACR_(\d+)-->` IN result RESULTS lt_bm.

    DATA lv_total_hunks TYPE i.
    IF lt_bm IS NOT INITIAL.
      lv_total_hunks = lines( lt_bm ).
      SORT lt_bm BY offset DESCENDING.
      LOOP AT lt_bm INTO DATA(ls_bm).
        DATA(lv_n) = lv_total_hunks - sy-tabix + 1.
        DATA(lv_ck) = |{ iv_key }~{ lv_n }|.
        DATA(lv_note_html) = zcl_code_acr_renderer=>render_decline_thread_html(
          iv_hunk_key      = lv_ck
          it_hunk_threads  = it_hunk_threads
          it_decline_notes = it_decline_notes
          it_declined      = it_declined ).
        DATA(lv_own_ck) = zcl_code_acr_state=>is_own_hunk(
          iv_hunk_key  = lv_ck
          it_hunk_info = it_hunk_info ).
        DATA(lv_global_ck) = zcl_code_acr_state=>get_hunk_global_action(
          iv_hunk_key     = lv_ck
          it_hunk_actions = it_hunk_actions ).

        DATA lv_btn TYPE string.
        IF lv_own_ck = abap_true
           AND NOT line_exists( it_approved[ table_line = lv_ck ] )
           AND NOT line_exists( it_declined[ table_line = lv_ck ] )
           AND lv_global_ck IS INITIAL.
          lv_btn = |<a id="acr_c{ lv_n }"></a>| &&
                   zcl_code_acr_renderer=>render_comment_links(
                     iv_hunk_key     = lv_ck
                     it_hunk_threads = it_hunk_threads
                     iv_ai_enabled   = iv_ai_enabled ).
        ELSEIF line_exists( it_approved[ table_line = lv_ck ] ).
          lv_btn = |<a id="acr_c{ lv_n }"></a>| &&
                   `<span style="font-style:normal;font-weight:bold;color:#27ae60"> &#10003; approved</span>` &&
                   zcl_code_acr_renderer=>render_hunk_action_meta(
                     iv_hunk_key     = lv_ck
                     iv_action       = 'A'
                     it_hunk_actions = it_hunk_actions ).
          IF lv_own_ck = abap_false.
            lv_btn = lv_btn &&
                     |<a href="sapevent:undo~{ lv_ck }"| &&
                     ` style="margin-left:8px;background:#95a5a6;color:#fff;font-weight:bold;` &&
                     `text-decoration:none;font-style:normal;font-size:11px;border-radius:3px;padding:2px 7px">Undo</a>`.
          ENDIF.
          lv_btn = lv_btn && zcl_code_acr_renderer=>render_comment_links(
            iv_hunk_key     = lv_ck
            it_hunk_threads = it_hunk_threads
            iv_ai_enabled   = iv_ai_enabled ).
        ELSEIF line_exists( it_declined[ table_line = lv_ck ] ).
          lv_btn = |<a id="acr_c{ lv_n }"></a>| &&
                   `<span style="font-style:normal;font-weight:bold;color:#e74c3c"> &#10007; declined</span>` &&
                   zcl_code_acr_renderer=>render_hunk_action_meta(
                     iv_hunk_key     = lv_ck
                     iv_action       = 'D'
                     it_hunk_actions = it_hunk_actions ).
          IF lv_own_ck = abap_false.
            lv_btn = lv_btn &&
                     |<a href="sapevent:undo~{ lv_ck }"| &&
                     ` style="margin-left:8px;background:#95a5a6;color:#fff;font-weight:bold;` &&
                     `text-decoration:none;font-style:normal;font-size:11px;border-radius:3px;padding:2px 7px">Undo</a>` &&
                     |<a href="sapevent:approve~{ lv_ck }"| &&
                     ` style="margin-left:4px;background:#27ae60;color:#fff;font-weight:bold;` &&
                     `text-decoration:none;font-style:normal;font-size:11px;border-radius:3px;padding:2px 7px">&#10003; Approve</a>`.
          ENDIF.
          lv_btn = lv_btn && zcl_code_acr_renderer=>render_comment_links(
            iv_hunk_key     = lv_ck
            it_hunk_threads = it_hunk_threads
            iv_ai_enabled   = iv_ai_enabled ).
        ELSEIF lv_global_ck = 'A' OR lv_global_ck = 'D'.
          DATA(lv_g_label) = COND string( WHEN lv_global_ck = 'A'
            THEN `<span style="font-style:normal;font-weight:bold;color:#27ae60"> &#10003; approved</span>`
            ELSE `<span style="font-style:normal;font-weight:bold;color:#e74c3c"> &#10007; declined</span>` ).
          lv_btn = |<a id="acr_c{ lv_n }"></a>| && lv_g_label &&
                   zcl_code_acr_renderer=>render_hunk_action_meta(
                     iv_hunk_key     = lv_ck
                     iv_action       = lv_global_ck
                     it_hunk_actions = it_hunk_actions ).
          IF lv_own_ck = abap_false.
            lv_btn = lv_btn &&
                     |<a href="sapevent:approve~{ lv_ck }"| &&
                     ` style="margin-left:8px;background:#27ae60;color:#fff;font-weight:bold;` &&
                     `text-decoration:none;font-style:normal;font-size:11px;border-radius:3px;padding:2px 7px">&#10003; Approve</a>` &&
                     |<a href="sapevent:decline~{ lv_ck }"| &&
                     ` style="margin-left:4px;background:#922b21;color:#fff;font-weight:bold;` &&
                     `text-decoration:none;font-style:normal;font-size:11px;border-radius:3px;padding:2px 7px">&#10007; Decline</a>`.
          ENDIF.
          lv_btn = lv_btn && zcl_code_acr_renderer=>render_comment_links(
            iv_hunk_key     = lv_ck
            it_hunk_threads = it_hunk_threads
            iv_ai_enabled   = iv_ai_enabled ).
        ELSE.
          lv_btn = |<a id="acr_c{ lv_n }"></a>|.
          IF lv_own_ck = abap_true.
            lv_btn = lv_btn &&
                     `<span style="font-style:normal;color:#7f8c8d"> &#9675; own block</span>` &&
                     zcl_code_acr_renderer=>render_comment_links(
                       iv_hunk_key     = lv_ck
                       it_hunk_threads = it_hunk_threads
                       iv_ai_enabled   = iv_ai_enabled ).
          ELSE.
            lv_btn = lv_btn &&
                     |<a href="sapevent:approve~{ lv_ck }"| &&
                     ` style="margin-left:8px;background:#27ae60;color:#fff;font-weight:bold;` &&
                     `text-decoration:none;font-style:normal;font-size:11px;border-radius:3px;padding:2px 7px">&#10003; Approve</a>` &&
                     |<a href="sapevent:decline~{ lv_ck }"| &&
                     ` style="margin-left:4px;background:#922b21;color:#fff;font-weight:bold;` &&
                     `text-decoration:none;font-style:normal;font-size:11px;border-radius:3px;padding:2px 7px">&#10007; Decline</a>` &&
                     zcl_code_acr_renderer=>render_comment_links(
                       iv_hunk_key     = lv_ck
                       it_hunk_threads = it_hunk_threads
                       iv_ai_enabled   = iv_ai_enabled ).
          ENDIF.
        ENDIF.

        IF lv_note_html IS NOT INITIAL.
          DATA(lv_after_ph) = ls_bm-offset + ls_bm-length.
          DATA(lv_tail) = result+lv_after_ph.
          DATA lv_tr_off TYPE i.
          FIND FIRST OCCURRENCE OF `</tr>` IN lv_tail MATCH OFFSET lv_tr_off.
          IF sy-subrc = 0.
            DATA(lv_ins_at) = lv_after_ph + lv_tr_off + 5.
            result = result(lv_ins_at) && lv_note_html && result+lv_ins_at.
          ENDIF.
        ENDIF.

        DATA(lv_ph) = |<!--ACR_{ lv_n }-->|.
        REPLACE FIRST OCCURRENCE OF lv_ph IN result WITH lv_btn.
      ENDLOOP.
    ELSE.
      CONSTANTS lc_sep1 TYPE string VALUE
        `<tr style="background:#f0f0f0;color:#888"><td class="ln">...</td><td class="cd">...</td></tr>`.
      CONSTANTS lc_sep2 TYPE string VALUE
        `<tr style="background:#f0f0f0;color:#888"><td class="ln">...</td><td class="cd">...</td><td class="sep"></td><td class="ln">...</td><td class="cd">...</td></tr>`.
      DATA lv_sn TYPE i VALUE 0.
      DATA lv_found TYPE abap_bool.
      DO.
        lv_found = abap_false.
        IF result CS lc_sep2.
          lv_found = abap_true.
          lv_sn = lv_sn + 1.
          DATA(lv_cell2) = acr_approve_cell(
            iv_key          = |{ iv_key }~{ lv_sn }|
            it_hunk_info    = it_hunk_info
            it_approved     = it_approved
            it_declined     = it_declined
            it_hunk_actions = it_hunk_actions
            it_hunk_threads = it_hunk_threads
            iv_ai_enabled   = iv_ai_enabled ).
          REPLACE FIRST OCCURRENCE OF lc_sep2 IN result WITH
            `<tr style="background:#f0f0f0;color:#888"><td class="ln">...</td>` &&
            `<td class="cd">...</td><td class="sep"></td><td class="ln">...</td>` &&
            lv_cell2 && `</tr>`.
        ELSEIF result CS lc_sep1.
          lv_found = abap_true.
          lv_sn = lv_sn + 1.
          DATA(lv_cell1) = acr_approve_cell(
            iv_key          = |{ iv_key }~{ lv_sn }|
            it_hunk_info    = it_hunk_info
            it_approved     = it_approved
            it_declined     = it_declined
            it_hunk_actions = it_hunk_actions
            it_hunk_threads = it_hunk_threads
            iv_ai_enabled   = iv_ai_enabled ).
          REPLACE FIRST OCCURRENCE OF lc_sep1 IN result WITH
            `<tr style="background:#f0f0f0;color:#888"><td class="ln">...</td>` &&
            lv_cell1 && `</tr>`.
        ENDIF.
        IF lv_found = abap_false. EXIT. ENDIF.
      ENDDO.
      lv_total_hunks = lv_sn.

      IF lv_sn = 0.
        lv_total_hunks = 1.
        result = replace( val = result sub = `</body>`
          with = acr_approve_fixed(
            iv_key          = |{ iv_key }~1|
            it_hunk_info    = it_hunk_info
            it_approved     = it_approved
            it_declined     = it_declined
            it_hunk_actions = it_hunk_actions
            it_hunk_threads = it_hunk_threads
            iv_ai_enabled   = iv_ai_enabled ) && `</body>` ).
      ENDIF.
    ENDIF.

    DATA lv_tld TYPE i.
    FIND FIRST OCCURRENCE OF '~' IN iv_key MATCH OFFSET lv_tld.
    IF sy-subrc = 0.
      DATA lv_type  TYPE versobjtyp.
      DATA lv_oname TYPE versobjnam.
      lv_type = iv_key(lv_tld).
      DATA lv_nstart TYPE i.
      lv_nstart = lv_tld + 1.
      lv_oname = iv_key+lv_nstart.
      READ TABLE ct_acr_stats ASSIGNING FIELD-SYMBOL(<acrs>)
        WITH KEY objtype = lv_type obj_name = lv_oname.
      IF sy-subrc = 0 AND lv_total_hunks > <acrs>-hunk_count.
        <acrs>-hunk_count = lv_total_hunks.
      ENDIF.
    ENDIF.

    result = replace( val = result sub = `</body>`
      with = build_approveall_btn(
        iv_obj_key      = iv_key
        iv_total_hunks  = lv_total_hunks
        it_approved     = it_approved
        it_declined     = it_declined
        it_hunk_actions = it_hunk_actions ) && `</body>` ).

    DATA(lv_back_btn) =
      `<div style="position:fixed;top:8px;left:8px;z-index:999">` &&
      `<a href="sapevent:back~0"` &&
      ` style="background:#3498db;color:#fff;padding:5px 14px;` &&
      `border-radius:4px;font:bold 12px Consolas,sans-serif;text-decoration:none">` &&
      `&larr; Back</a></div>`.
    result = replace( val = result sub = `</body>` with = lv_back_btn && `</body>` ).
    cv_html = result.
  ENDMETHOD.


  METHOD acr_approve_cell.
    DATA(lv_own_hunk) = zcl_code_acr_state=>is_own_hunk(
      iv_hunk_key  = iv_key
      it_hunk_info = it_hunk_info ).
    DATA(lv_global_action) = zcl_code_acr_state=>get_hunk_global_action(
      iv_hunk_key     = iv_key
      it_hunk_actions = it_hunk_actions ).
    IF line_exists( it_approved[ table_line = iv_key ] ).
      result = `<td class="cd" style="color:#27ae60;font-weight:bold">` &&
               `&#10003;&nbsp;approved` &&
               zcl_code_acr_renderer=>render_hunk_action_meta(
                 iv_hunk_key     = iv_key
                 iv_action       = 'A'
                 it_hunk_actions = it_hunk_actions ).
      IF lv_own_hunk = abap_false.
        result = result &&
                 |<a href="sapevent:undo~{ iv_key }"| &&
                 ` style="margin-left:8px;background:#95a5a6;color:#fff;font-weight:bold;` &&
                 `text-decoration:none;font-size:11px;border-radius:3px;padding:2px 7px">Undo</a>`.
      ENDIF.
      result = result && zcl_code_acr_renderer=>render_comment_links(
        iv_hunk_key     = iv_key
        it_hunk_threads = it_hunk_threads
        iv_ai_enabled   = iv_ai_enabled ) && `</td>`.
    ELSEIF line_exists( it_declined[ table_line = iv_key ] ).
      result = `<td class="cd" style="color:#e74c3c;font-weight:bold">` &&
               `&#10007;&nbsp;declined` &&
               zcl_code_acr_renderer=>render_hunk_action_meta(
                 iv_hunk_key     = iv_key
                 iv_action       = 'D'
                 it_hunk_actions = it_hunk_actions ).
      IF lv_own_hunk = abap_false.
        result = result &&
                 |<a href="sapevent:undo~{ iv_key }"| &&
                 ` style="margin-left:8px;background:#95a5a6;color:#fff;font-weight:bold;` &&
                 `text-decoration:none;font-size:11px;border-radius:3px;padding:2px 7px">Undo</a>`.
      ENDIF.
      result = result && zcl_code_acr_renderer=>render_comment_links(
        iv_hunk_key     = iv_key
        it_hunk_threads = it_hunk_threads
        iv_ai_enabled   = iv_ai_enabled ) && `</td>`.
    ELSEIF lv_global_action = 'A' OR lv_global_action = 'D'.
      IF lv_global_action = 'A'.
        result = `<td class="cd" style="color:#27ae60;font-weight:bold">` &&
                 `&#10003;&nbsp;approved` &&
                 zcl_code_acr_renderer=>render_hunk_action_meta(
                   iv_hunk_key     = iv_key
                   iv_action       = 'A'
                   it_hunk_actions = it_hunk_actions ).
      ELSE.
        result = `<td class="cd" style="color:#e74c3c;font-weight:bold">` &&
                 `&#10007;&nbsp;declined` &&
                 zcl_code_acr_renderer=>render_hunk_action_meta(
                   iv_hunk_key     = iv_key
                   iv_action       = 'D'
                   it_hunk_actions = it_hunk_actions ).
      ENDIF.
      IF lv_own_hunk = abap_false.
        result = result &&
                 |<a href="sapevent:approve~{ iv_key }"| &&
                 | style="margin-left:12px;background:#27ae60;color:#fff;| &&
                 |font-size:11px;font-weight:bold;text-decoration:none;| &&
                 |border-radius:3px;padding:2px 7px">&#10003;&nbsp;approve</a>| &&
                 |<a href="sapevent:decline~{ iv_key }"| &&
                 | style="margin-left:8px;background:#922b21;color:#fff;| &&
                 |font-size:11px;font-weight:bold;text-decoration:none;| &&
                 |border-radius:3px;padding:2px 7px">&#10007;&nbsp;decline</a>|.
      ENDIF.
      result = result && zcl_code_acr_renderer=>render_comment_links(
        iv_hunk_key     = iv_key
        it_hunk_threads = it_hunk_threads
        iv_ai_enabled   = iv_ai_enabled ) && `</td>`.
    ELSEIF lv_own_hunk = abap_true.
      result = |<td class="cd">...| &&
               |<span style="margin-left:12px;color:#7f8c8d;font-weight:bold">&#9675;&nbsp;own block</span>| &&
               zcl_code_acr_renderer=>render_comment_links(
                 iv_hunk_key     = iv_key
                 it_hunk_threads = it_hunk_threads
                 iv_ai_enabled   = iv_ai_enabled ) && `</td>`.
    ELSE.
      result = |<td class="cd">...| &&
               |<a href="sapevent:approve~{ iv_key }"| &&
               | style="margin-left:12px;background:#27ae60;color:#fff;| &&
               |font-size:11px;font-weight:bold;text-decoration:none;| &&
               |border-radius:3px;padding:2px 7px">&#10003;&nbsp;approve</a>| &&
               |<a href="sapevent:decline~{ iv_key }"| &&
               | style="margin-left:8px;background:#922b21;color:#fff;| &&
               |font-size:11px;font-weight:bold;text-decoration:none;| &&
               |border-radius:3px;padding:2px 7px">&#10007;&nbsp;decline</a>| &&
               zcl_code_acr_renderer=>render_comment_links(
                 iv_hunk_key     = iv_key
                 it_hunk_threads = it_hunk_threads
                 iv_ai_enabled   = iv_ai_enabled ) && `</td>`.
    ENDIF.
  ENDMETHOD.


  METHOD acr_approve_fixed.
    DATA(lv_own_hunk) = zcl_code_acr_state=>is_own_hunk(
      iv_hunk_key  = iv_key
      it_hunk_info = it_hunk_info ).
    DATA(lv_global_action) = zcl_code_acr_state=>get_hunk_global_action(
      iv_hunk_key     = iv_key
      it_hunk_actions = it_hunk_actions ).
    IF line_exists( it_approved[ table_line = iv_key ] ).
      result =
        `<div style="position:fixed;top:8px;right:12px;z-index:999;display:flex;gap:6px;align-items:center">` &&
        `<span style="background:#27ae60;color:#fff;padding:4px 14px;` &&
        `border-radius:4px;font:bold 12px Consolas,sans-serif">&#10003;&nbsp;Approved</span>` &&
        zcl_code_acr_renderer=>render_hunk_action_meta(
          iv_hunk_key     = iv_key
          iv_action       = 'A'
          it_hunk_actions = it_hunk_actions ).
      IF lv_own_hunk = abap_false.
        result = result &&
          |<a href="sapevent:undo~{ iv_key }"| &&
          ` style="background:#95a5a6;color:#fff;padding:4px 10px;` &&
          `border-radius:4px;font:bold 12px Consolas,sans-serif;text-decoration:none">Undo</a>`.
      ENDIF.
      result = result && zcl_code_acr_renderer=>render_comment_links(
        iv_hunk_key     = iv_key
        it_hunk_threads = it_hunk_threads
        iv_ai_enabled   = iv_ai_enabled ) && `</div>`.
    ELSEIF line_exists( it_declined[ table_line = iv_key ] ).
      result =
        `<div style="position:fixed;top:8px;right:12px;z-index:999;display:flex;gap:6px;align-items:center">` &&
        `<span style="background:#e74c3c;color:#fff;padding:4px 14px;` &&
        `border-radius:4px;font:bold 12px Consolas,sans-serif">&#10007;&nbsp;Declined</span>` &&
        zcl_code_acr_renderer=>render_hunk_action_meta(
          iv_hunk_key     = iv_key
          iv_action       = 'D'
          it_hunk_actions = it_hunk_actions ).
      IF lv_own_hunk = abap_false.
        result = result &&
          |<a href="sapevent:undo~{ iv_key }"| &&
          ` style="background:#95a5a6;color:#fff;padding:4px 10px;` &&
          `border-radius:4px;font:bold 12px Consolas,sans-serif;text-decoration:none">Undo</a>`.
      ENDIF.
      result = result && zcl_code_acr_renderer=>render_comment_links(
        iv_hunk_key     = iv_key
        it_hunk_threads = it_hunk_threads
        iv_ai_enabled   = iv_ai_enabled ) && `</div>`.
    ELSEIF lv_global_action = 'A' OR lv_global_action = 'D'.
      result =
        `<div style="position:fixed;top:8px;right:12px;z-index:999;display:flex;gap:6px;align-items:center">`.
      IF lv_global_action = 'A'.
        result = result &&
          `<span style="background:#27ae60;color:#fff;padding:4px 14px;` &&
          `border-radius:4px;font:bold 12px Consolas,sans-serif">&#10003;&nbsp;Approved</span>` &&
          zcl_code_acr_renderer=>render_hunk_action_meta(
            iv_hunk_key     = iv_key
            iv_action       = 'A'
            it_hunk_actions = it_hunk_actions ).
      ELSE.
        result = result &&
          `<span style="background:#e74c3c;color:#fff;padding:4px 14px;` &&
          `border-radius:4px;font:bold 12px Consolas,sans-serif">&#10007;&nbsp;Declined</span>` &&
          zcl_code_acr_renderer=>render_hunk_action_meta(
            iv_hunk_key     = iv_key
            iv_action       = 'D'
            it_hunk_actions = it_hunk_actions ).
      ENDIF.
      IF lv_own_hunk = abap_false.
        result = result &&
          |<a href="sapevent:approve~{ iv_key }"| &&
          ` style="background:#27ae60;color:#fff;padding:4px 14px;` &&
          `border-radius:4px;font:bold 12px Consolas,sans-serif;text-decoration:none">` &&
          `&#10003;&nbsp;Approve</a>` &&
          |<a href="sapevent:decline~{ iv_key }"| &&
          ` style="background:#922b21;color:#fff;padding:4px 14px;` &&
          `border-radius:4px;font:bold 12px Consolas,sans-serif;text-decoration:none">` &&
          `&#10007;&nbsp;Decline</a>`.
      ENDIF.
      result = result && zcl_code_acr_renderer=>render_comment_links(
        iv_hunk_key     = iv_key
        it_hunk_threads = it_hunk_threads
        iv_ai_enabled   = iv_ai_enabled ) && `</div>`.
    ELSEIF lv_own_hunk = abap_true.
      result =
        |<div style="position:fixed;top:8px;right:12px;z-index:999;display:flex;gap:6px">| &&
        `<span style="background:#7f8c8d;color:#fff;padding:4px 14px;` &&
        `border-radius:4px;font:bold 12px Consolas,sans-serif">&#9675;&nbsp;Own Block</span>` &&
        zcl_code_acr_renderer=>render_comment_links(
          iv_hunk_key     = iv_key
          it_hunk_threads = it_hunk_threads
          iv_ai_enabled   = iv_ai_enabled ) && `</div>`.
    ELSE.
      result =
        |<div style="position:fixed;top:8px;right:12px;z-index:999;display:flex;gap:6px">| &&
        |<a href="sapevent:approve~{ iv_key }"| &&
        ` style="background:#27ae60;color:#fff;padding:4px 14px;` &&
        `border-radius:4px;font:bold 12px Consolas,sans-serif;text-decoration:none">` &&
        `&#10003;&nbsp;Approve</a>` &&
        |<a href="sapevent:decline~{ iv_key }"| &&
        ` style="background:#922b21;color:#fff;padding:4px 14px;` &&
        `border-radius:4px;font:bold 12px Consolas,sans-serif;text-decoration:none">` &&
        `&#10007;&nbsp;Decline</a>` &&
        zcl_code_acr_renderer=>render_comment_links(
          iv_hunk_key     = iv_key
          it_hunk_threads = it_hunk_threads
          iv_ai_enabled   = iv_ai_enabled ) && `</div>`.
    ENDIF.
  ENDMETHOD.


  METHOD build_approveall_btn.
    DATA lv_appr_cnt TYPE i.
    DATA lv_decl_cnt TYPE i.
    DO iv_total_hunks TIMES.
      DATA(lv_ck) = |{ iv_obj_key }~{ sy-index }|.
      DATA(lv_ga) = zcl_code_acr_state=>get_hunk_global_action(
        iv_hunk_key     = lv_ck
        it_hunk_actions = it_hunk_actions ).
      IF line_exists( it_approved[ table_line = lv_ck ] ) OR lv_ga = 'A'.
        lv_appr_cnt = lv_appr_cnt + 1.
      ELSEIF line_exists( it_declined[ table_line = lv_ck ] ) OR lv_ga = 'D'.
        lv_decl_cnt = lv_decl_cnt + 1.
      ENDIF.
    ENDDO.
    DATA(lv_badge) =
      |<span style="color:#27ae60">&#10003;{ lv_appr_cnt }</span>| &&
      | <span style="color:#e74c3c">&#10007;{ lv_decl_cnt }</span>| &&
      | <span style="color:#ccc">/{ iv_total_hunks }</span>|.
    IF lv_appr_cnt >= iv_total_hunks AND iv_total_hunks > 0.
      result =
        `<div style="position:fixed;top:8px;right:12px;z-index:999;` &&
        `background:#27ae60;color:#fff;padding:5px 16px;border-radius:4px;` &&
        `font:bold 12px Consolas,sans-serif">` &&
        |&#10003; All Approved &nbsp;{ lv_badge }</div>|.
    ELSE.
      result =
        `<div style="position:fixed;top:8px;right:12px;z-index:999">` &&
        `<a href="sapevent:approveall~` && iv_obj_key && `"` &&
        ` style="background:#2F2F2F;color:#fff;padding:5px 16px;` &&
        `border-radius:4px;font:bold 12px Consolas,sans-serif;` &&
        `text-decoration:none">` &&
        |&#10003; Approve All &nbsp;{ lv_badge }</a></div>|.
    ENDIF.
  ENDMETHOD.

ENDCLASS.
