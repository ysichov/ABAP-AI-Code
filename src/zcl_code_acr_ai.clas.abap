CLASS zcl_code_acr_ai DEFINITION
  PUBLIC
  FINAL
  CREATE PRIVATE.

  PUBLIC SECTION.
    CLASS-METHODS is_enabled
      IMPORTING
        iv_destination   TYPE text255
        iv_model         TYPE text255
        iv_apikey        TYPE text255
      RETURNING
        VALUE(result)    TYPE abap_bool.

    TYPES ty_t_hunk_info_std TYPE STANDARD TABLE OF zif_code_acr_types=>ty_hunk_info WITH DEFAULT KEY.

    CLASS-METHODS build_hunk_prompt
      IMPORTING
        iv_hunk_key      TYPE string
        it_hunk_info     TYPE zif_code_acr_types=>ty_t_hunk_info
        it_diff_data     TYPE zif_code_acr_types=>ty_t_diff_data OPTIONAL
        iv_ignore_case   TYPE abap_bool
      RETURNING
        VALUE(result)    TYPE string.

    CLASS-METHODS build_prompt_page_html
      IMPORTING
        iv_object_name   TYPE string
        iv_compact       TYPE abap_bool
        iv_ignore_case   TYPE abap_bool
        it_diff_data     TYPE zif_code_acr_types=>ty_t_diff_data OPTIONAL
        it_hunks         TYPE ty_t_hunk_info_std
      RETURNING
        VALUE(result)    TYPE string.
    CLASS-METHODS get_hunk_thread
      IMPORTING
        is_hunk          TYPE zif_code_acr_types=>ty_hunk_info
        it_hunk_threads  TYPE zif_code_acr_types=>ty_t_hunk_threads
      RETURNING
        VALUE(result)    TYPE zif_code_acr_types=>ty_hunk_thread.

    CLASS-METHODS get_hunk_comment
      IMPORTING
        iv_hunk_key      TYPE string
        it_hunk_info     TYPE zif_code_acr_types=>ty_t_hunk_info
        it_hunk_threads  TYPE zif_code_acr_types=>ty_t_hunk_threads
      RETURNING
        VALUE(result)    TYPE string.

    CLASS-METHODS get_summary_key
      IMPORTING
        iv_objtype       TYPE versobjtyp
        iv_objname       TYPE versobjnam
      RETURNING
        VALUE(result)    TYPE string.

    CLASS-METHODS get_hunk_scroll_anchor
      IMPORTING
        iv_hunk_key      TYPE string
      RETURNING
        VALUE(result)    TYPE string.

    CLASS-METHODS get_summary_scroll_anchor
      IMPORTING
        iv_objtype       TYPE versobjtyp
        iv_objname       TYPE versobjnam
      RETURNING
        VALUE(result)    TYPE string.

    CLASS-METHODS render_summary_html
      IMPORTING
        iv_objtype       TYPE versobjtyp
        iv_objname       TYPE versobjnam
        it_hunk_threads  TYPE zif_code_acr_types=>ty_t_hunk_threads
      RETURNING
        VALUE(result)    TYPE string.

    CLASS-METHODS save_summary
      IMPORTING
        iv_objtype       TYPE versobjtyp
        iv_objname       TYPE versobjnam
        iv_text          TYPE string
        it_hunk_info     TYPE zif_code_acr_types=>ty_t_hunk_info
      CHANGING
        ct_hunk_threads  TYPE zif_code_acr_types=>ty_t_hunk_threads.
ENDCLASS.


CLASS zcl_code_acr_ai IMPLEMENTATION.

  METHOD is_enabled.
    result = COND #( WHEN iv_destination IS NOT INITIAL
                       AND iv_model IS NOT INITIAL
                       AND iv_apikey IS NOT INITIAL
                     THEN abap_true ELSE abap_false ).
  ENDMETHOD.


  METHOD build_hunk_prompt.
    DATA(lv_nl) = cl_abap_char_utilities=>newline.

    READ TABLE it_hunk_info INTO DATA(ls_hunk)
      WITH TABLE KEY hunk_key = iv_hunk_key.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.

    DATA lt_src_old TYPE abaptxt255_tab.
    DATA lt_src_new TYPE abaptxt255_tab.
    DATA lt_obj_diff TYPE zif_code_popup_types=>ty_t_diff.

    READ TABLE it_diff_data INTO DATA(ls_diff_data)
      WITH KEY key-objtype = ls_hunk-objtype
               key-objname = ls_hunk-obj_name
               key-versno_o = ls_hunk-versno_old
               key-versno_n = ls_hunk-versno_new
               key-ignore_case = iv_ignore_case.
    IF sy-subrc = 0.
      lt_obj_diff = ls_diff_data-diff.
    ENDIF.

    IF lt_obj_diff IS INITIAL.
      IF ls_hunk-versno_old IS NOT INITIAL.
        lt_src_old = zcl_code_popup_data=>get_ver_source(
          i_objtype = ls_hunk-objtype
          i_objname = ls_hunk-obj_name
          i_versno  = ls_hunk-versno_old ).
      ENDIF.
      lt_src_new = zcl_code_popup_data=>get_ver_source(
        i_objtype = ls_hunk-objtype
        i_objname = ls_hunk-obj_name
        i_versno  = ls_hunk-versno_new ).

      IF ls_hunk-versno_old IS INITIAL.
        LOOP AT lt_src_new INTO DATA(ls_new_line).
          APPEND VALUE zif_code_popup_types=>ty_diff_op(
            op   = '+'
            text = CONV string( ls_new_line ) ) TO lt_obj_diff.
        ENDLOOP.
      ELSE.
        lt_obj_diff = zcl_code_popup_diff=>compute_diff(
          it_old        = lt_src_old
          it_new        = lt_src_new
          i_title       = CONV #( ls_hunk-obj_name )
          i_confirm_key = |ASKAI~{ ls_hunk-objtype }~{ ls_hunk-obj_name }|
          i_ignore_case = iv_ignore_case ).
      ENDIF.
    ENDIF.

    DATA lv_hunk_cnt TYPE i.
    DATA lv_in_block TYPE abap_bool.
    TYPES:
      BEGIN OF ty_ai_line,
        line TYPE i,
        text TYPE string,
      END OF ty_ai_line.
    DATA lt_deleted TYPE STANDARD TABLE OF ty_ai_line WITH DEFAULT KEY.
    DATA lt_inserted TYPE STANDARD TABLE OF ty_ai_line WITH DEFAULT KEY.
    DATA lv_hunk_code TYPE string.
    DATA lv_old_line TYPE i.
    DATA lv_new_line TYPE i.

    LOOP AT lt_obj_diff INTO DATA(ls_op).
      CASE ls_op-op.
        WHEN '+' OR '-'.
          IF lv_in_block = abap_false.
            lv_in_block = abap_true.
            CLEAR: lt_deleted, lt_inserted.
          ENDIF.
          IF ls_op-op = '+'.
            lv_new_line = lv_new_line + 1.
            APPEND VALUE ty_ai_line( line = lv_new_line text = ls_op-text ) TO lt_inserted.
          ELSE.
            lv_old_line = lv_old_line + 1.
            APPEND VALUE ty_ai_line( line = lv_old_line text = ls_op-text ) TO lt_deleted.
          ENDIF.

        WHEN OTHERS.
          IF lv_in_block = abap_true.
            IF lt_deleted IS NOT INITIAL OR lt_inserted IS NOT INITIAL.
              lv_hunk_cnt = lv_hunk_cnt + 1.
              IF lv_hunk_cnt = ls_hunk-hunk_no.
                EXIT.
              ENDIF.
            ENDIF.
            lv_in_block = abap_false.
            CLEAR: lt_deleted, lt_inserted.
          ENDIF.
          IF ls_op-op = '='.
            lv_old_line = lv_old_line + 1.
            lv_new_line = lv_new_line + 1.
          ENDIF.
      ENDCASE.
    ENDLOOP.

    IF lv_hunk_cnt <> ls_hunk-hunk_no AND lv_in_block = abap_true
       AND ( lt_deleted IS NOT INITIAL OR lt_inserted IS NOT INITIAL ).
      lv_hunk_cnt = lv_hunk_cnt + 1.
    ENDIF.

    IF lv_hunk_cnt <> ls_hunk-hunk_no.
      RETURN.
    ENDIF.

    DATA(lv_kind) = COND string(
      WHEN lt_deleted IS NOT INITIAL AND lt_inserted IS NOT INITIAL THEN `changed`
      WHEN lt_inserted IS NOT INITIAL                              THEN `added`
      ELSE                                                               `deleted` ).

    lv_hunk_code = |>>> start of { lv_kind } block for LLM| && lv_nl.
    LOOP AT lt_deleted INTO DATA(ls_deleted).
      lv_hunk_code = lv_hunk_code && |- { ls_deleted-line } | && ` | ` && ls_deleted-text && lv_nl.
    ENDLOOP.
    LOOP AT lt_inserted INTO DATA(ls_inserted).
      lv_hunk_code = lv_hunk_code && |+ { ls_inserted-line } | && ` | ` && ls_inserted-text && lv_nl.
    ENDLOOP.
    lv_hunk_code = lv_hunk_code && |<<< end of { lv_kind } block for LLM|.

    DATA lv_obj_name TYPE string.
    IF ls_hunk-class_name IS NOT INITIAL.
      lv_obj_name = | Class { ls_hunk-class_name } method { ls_hunk-display_name }|.
    ELSE.
      lv_obj_name = |{ ls_hunk-objtype } { ls_hunk-obj_name }|.
    ENDIF.

    result =
      `You are ABAP code business reviewer. Very very Brifly describe meaning of the changes. - deleted, + inserted. Just describe what you see - no deep research. No suggests.` && lv_nl &&
      lv_nl &&
      `Output format - Object name` && lv_nl &&
      lv_nl &&
      `Below are code changes` && lv_nl &&
      'Object name: ' && lv_obj_name  && lv_nl &&
      lv_nl &&
      lv_hunk_code.
  ENDMETHOD.




  METHOD build_prompt_page_html.
    DATA(lt_hunks) = it_hunks.

    " Build page
    DATA(lv_nl)  = cl_abap_char_utilities=>newline.
    DATA(lv_css) =
      `body{font:13px/1.45 Consolas,monospace;padding:20px 28px;background:#fff;color:#222}` &&
      `h2{color:#2c3e50;border-bottom:2px solid #3498db;padding-bottom:6px;margin:0 0 16px}` &&
      `pre{margin:0 0 0 0;padding:10px 12px;background:#fafafa;border:1px solid #ddd;` &&
      `white-space:pre-wrap;border-top:none}` &&
      `.hdr{background:#dbe9ff;color:#2c3e50;font-weight:bold;padding:5px 12px;` &&
      `margin:20px 0 0 0;border:1px solid #b0c8f0}` &&
      `.back{position:fixed;top:8px;left:8px;z-index:999;background:#3498db;color:#fff;` &&
      `padding:4px 10px;border-radius:4px;text-decoration:none;` &&
      `font:bold 12px Consolas,monospace;box-shadow:0 1px 4px rgba(0,0,0,.25)}`.

    DATA(lv_mode) = COND string( WHEN iv_compact = abap_true THEN `Compact` ELSE `Full` ).
    DATA(lv_html) =
      |<!DOCTYPE html><html><head><meta charset="utf-8"><style>{ lv_css }</style></head><body>| &&
      |<a class="back" href="sapevent:back~0">&#8592; Back</a>| &&
      |<h2>AI prompt &#8212; { escape( val = CONV string( iv_object_name ) format = cl_abap_format=>e_html_text ) }| &&
      | / { lv_mode }</h2>| &&
      |<pre>Check please all changes in the code and provide a brief change description</pre>|.

    IF lt_hunks IS INITIAL.
      lv_html = lv_html && `<p style="color:#888">No changed blocks found.</p></body></html>`.
      result = lv_html.
      RETURN.
    ENDIF.

    IF iv_compact = abap_false.
      DATA lv_full_cur_obj_key TYPE string.
      LOOP AT lt_hunks INTO DATA(ls_full_hunk).
        DATA(lv_full_obj_key) = |{ ls_full_hunk-objtype }~{ ls_full_hunk-obj_name }|.
        IF lv_full_obj_key = lv_full_cur_obj_key.
          CONTINUE.
        ENDIF.
        lv_full_cur_obj_key = lv_full_obj_key.

        DATA lt_full_src_old TYPE abaptxt255_tab.
        DATA lt_full_src_new TYPE abaptxt255_tab.
        DATA lt_full_diff TYPE zif_code_popup_types=>ty_t_diff.
        CLEAR: lt_full_src_old, lt_full_src_new, lt_full_diff.

        READ TABLE it_diff_data INTO DATA(ls_full_diff_data)
          WITH KEY key-objtype = ls_full_hunk-objtype
                   key-objname = ls_full_hunk-obj_name
                   key-versno_o = ls_full_hunk-versno_old
                   key-versno_n = ls_full_hunk-versno_new
                   key-ignore_case = iv_ignore_case.
        IF sy-subrc = 0.
          lt_full_diff = ls_full_diff_data-diff.
        ENDIF.

        IF lt_full_diff IS INITIAL.
          IF ls_full_hunk-versno_old IS NOT INITIAL.
            lt_full_src_old = zcl_code_popup_data=>get_ver_source(
              i_objtype = ls_full_hunk-objtype
              i_objname = ls_full_hunk-obj_name
              i_versno  = ls_full_hunk-versno_old ).
          ENDIF.
          lt_full_src_new = zcl_code_popup_data=>get_ver_source(
            i_objtype = ls_full_hunk-objtype
            i_objname = ls_full_hunk-obj_name
            i_versno  = ls_full_hunk-versno_new ).

          IF ls_full_hunk-versno_old IS INITIAL.
            LOOP AT lt_full_src_new INTO DATA(ls_full_new_line).
              APPEND VALUE zif_code_popup_types=>ty_diff_op( op = '+' text = CONV string( ls_full_new_line ) ) TO lt_full_diff.
            ENDLOOP.
          ELSE.
            lt_full_diff = zcl_code_popup_diff=>compute_diff(
              it_old        = lt_full_src_old
              it_new        = lt_full_src_new
              i_title       = CONV #( ls_full_hunk-obj_name )
              i_confirm_key = |AIPROMPTFULL~{ lv_full_obj_key }|
              i_ignore_case = iv_ignore_case ).
          ENDIF.
        ENDIF.

        DATA(lv_full_disp) = COND string(
          WHEN ls_full_hunk-class_name IS NOT INITIAL AND ls_full_hunk-display_name IS NOT INITIAL
          THEN |{ ls_full_hunk-class_name }=>{ ls_full_hunk-display_name }|
          WHEN ls_full_hunk-display_name IS NOT INITIAL THEN ls_full_hunk-display_name
          ELSE CONV string( ls_full_hunk-obj_name ) ).

        DATA lv_full_code TYPE string.
        DATA lv_full_old_line TYPE i.
        DATA lv_full_new_line TYPE i.
        CLEAR: lv_full_code, lv_full_old_line, lv_full_new_line.
        LOOP AT lt_full_diff INTO DATA(ls_full_op).
          DATA(lv_full_text) = escape( val = ls_full_op-text format = cl_abap_format=>e_html_text ).
          CASE ls_full_op-op.
            WHEN '='.
              lv_full_old_line = lv_full_old_line + 1.
              lv_full_new_line = lv_full_new_line + 1.
              lv_full_code = lv_full_code && |  { lv_full_new_line } | && ` | ` && lv_full_text && lv_nl.
            WHEN '+'.
              lv_full_new_line = lv_full_new_line + 1.
              lv_full_code = lv_full_code && |+ { lv_full_new_line } | && ` | ` && lv_full_text && lv_nl.
            WHEN '-'.
              lv_full_old_line = lv_full_old_line + 1.
              lv_full_code = lv_full_code && |- { lv_full_old_line } | && ` | ` && lv_full_text && lv_nl.
          ENDCASE.
        ENDLOOP.

        lv_html = lv_html &&
          |<div class="hdr">| &&
          |{ escape( val = CONV string( ls_full_hunk-objtype ) format = cl_abap_format=>e_html_text ) }: | &&
          |{ escape( val = lv_full_disp format = cl_abap_format=>e_html_text ) }| &&
          | &nbsp;<span style="color:#7f8c99;font-weight:normal">full diff</span></div>| &&
          |<pre>| &&
          |>>> start of full code diff for LLM| && lv_nl &&
          lv_full_code &&
          |<<< end of full code diff for LLM| &&
          |</pre>|.
      ENDLOOP.

      lv_html = lv_html && `</body></html>`.
      result = lv_html.
      RETURN.
    ENDIF.

    " Process hunks grouped by object to avoid calling compute_diff multiple times
    DATA lv_cur_obj_key TYPE string.
    DATA lt_obj_diff    TYPE zif_code_popup_types=>ty_t_diff.

    LOOP AT lt_hunks INTO DATA(ls_hunk).

      DATA(lv_obj_key) = |{ ls_hunk-objtype }~{ ls_hunk-obj_name }|.

      " Recompute diff only when object changes
      IF lv_obj_key <> lv_cur_obj_key.
        lv_cur_obj_key = lv_obj_key.
        CLEAR lt_obj_diff.

        DATA lt_src_old TYPE abaptxt255_tab.
        DATA lt_src_new TYPE abaptxt255_tab.
        CLEAR: lt_src_old, lt_src_new.

        READ TABLE it_diff_data INTO DATA(ls_obj_diff_data)
          WITH KEY key-objtype = ls_hunk-objtype
                   key-objname = ls_hunk-obj_name
                   key-versno_o = ls_hunk-versno_old
                   key-versno_n = ls_hunk-versno_new
                   key-ignore_case = iv_ignore_case.
        IF sy-subrc = 0.
          lt_obj_diff = ls_obj_diff_data-diff.
        ENDIF.

        IF lt_obj_diff IS INITIAL.
          IF ls_hunk-versno_old IS NOT INITIAL.
            lt_src_old = zcl_code_popup_data=>get_ver_source(
              i_objtype = ls_hunk-objtype
              i_objname = ls_hunk-obj_name
              i_versno  = ls_hunk-versno_old ).
          ENDIF.
          lt_src_new = zcl_code_popup_data=>get_ver_source(
            i_objtype = ls_hunk-objtype
            i_objname = ls_hunk-obj_name
            i_versno  = ls_hunk-versno_new ).

          " For new objects (no old version) reconstruct diff as pure '+' stream,
          " matching the same logic used in cr_precompute_part.
          IF ls_hunk-versno_old IS INITIAL.
            LOOP AT lt_src_new INTO DATA(ls_new_line).
              APPEND VALUE zif_code_popup_types=>ty_diff_op( op = '+' text = CONV string( ls_new_line ) ) TO lt_obj_diff.
            ENDLOOP.
          ELSE.
            lt_obj_diff = zcl_code_popup_diff=>compute_diff(
              it_old        = lt_src_old
              it_new        = lt_src_new
              i_title       = CONV #( ls_hunk-obj_name )
              i_confirm_key = |AIPROMPT~{ lv_obj_key }|
              i_ignore_case = iv_ignore_case ).
          ENDIF.
        ENDIF.
      ENDIF.

      " Walk diff stream and find hunk #ls_hunk-hunk_no
      " IMPORTANT: all accumulators must be cleared at the top of each hunk iteration
      TYPES:
        BEGIN OF ty_ai_prompt_line,
          line TYPE i,
          text TYPE string,
        END OF ty_ai_prompt_line.
      DATA lv_hunk_cnt  TYPE i.
      DATA lv_in_block  TYPE abap_bool.
      DATA lt_del       TYPE STANDARD TABLE OF ty_ai_prompt_line WITH DEFAULT KEY.
      DATA lt_ins       TYPE STANDARD TABLE OF ty_ai_prompt_line WITH DEFAULT KEY.
      DATA lv_hunk_code TYPE string.
      DATA lv_prompt_old_line TYPE i.
      DATA lv_prompt_new_line TYPE i.
      CLEAR: lv_hunk_cnt, lv_in_block, lt_del, lt_ins, lv_hunk_code,
             lv_prompt_old_line, lv_prompt_new_line.

      LOOP AT lt_obj_diff INTO DATA(ls_op).
        CASE ls_op-op.
          WHEN '+' OR '-'.
            IF lv_in_block = abap_false.
              lv_in_block = abap_true.
              CLEAR: lt_del, lt_ins.
            ENDIF.
            IF ls_op-op = '+'.
              lv_prompt_new_line = lv_prompt_new_line + 1.
              APPEND VALUE ty_ai_prompt_line( line = lv_prompt_new_line text = ls_op-text ) TO lt_ins.
            ELSE.
              lv_prompt_old_line = lv_prompt_old_line + 1.
              APPEND VALUE ty_ai_prompt_line( line = lv_prompt_old_line text = ls_op-text ) TO lt_del.
            ENDIF.

          WHEN OTHERS.
            IF lv_in_block = abap_true.
              IF lt_del IS NOT INITIAL OR lt_ins IS NOT INITIAL.
                lv_hunk_cnt = lv_hunk_cnt + 1.

                IF lv_hunk_cnt = ls_hunk-hunk_no.
                  " change_kind values from cr_precompute_part: 'changed', 'added', 'deleted'
                  DATA(lv_kind) = COND string(
                    WHEN lt_del IS NOT INITIAL AND lt_ins IS NOT INITIAL THEN `changed`
                    WHEN lt_ins IS NOT INITIAL                            THEN `added`
                    ELSE                                                       `deleted` ).
                  lv_hunk_code = |>>> start of { lv_kind } block for LLM| && lv_nl.
                  " op='+' in compute_diff = inserted line, op='-' = deleted line

                  LOOP AT lt_ins INTO DATA(ls_il).
                    lv_hunk_code = lv_hunk_code &&
                      |+ { ls_il-line } | && ` | ` &&
                      |{ escape( val = ls_il-text format = cl_abap_format=>e_html_text ) }| && lv_nl.
                  ENDLOOP.
                  LOOP AT lt_del INTO DATA(ls_dl).
                    lv_hunk_code = lv_hunk_code &&
                      |- { ls_dl-line } | && ` | ` &&
                      |{ escape( val = ls_dl-text format = cl_abap_format=>e_html_text ) }| && lv_nl.
                  ENDLOOP.
                  lv_hunk_code = lv_hunk_code && |&lt;&lt;&lt; end of { lv_kind } block for LLM| && lv_nl.
                ENDIF.
              ENDIF.
              lv_in_block = abap_false.
              CLEAR: lt_del, lt_ins.

              IF lv_hunk_cnt >= ls_hunk-hunk_no.
                EXIT.
              ENDIF.
            ENDIF.
            IF ls_op-op = '='.
              lv_prompt_old_line = lv_prompt_old_line + 1.
              lv_prompt_new_line = lv_prompt_new_line + 1.
            ENDIF.
        ENDCASE.
      ENDLOOP.

      " Handle diff ending without trailing context line
      IF lv_in_block = abap_true AND lv_hunk_code IS INITIAL.
        IF lt_del IS NOT INITIAL OR lt_ins IS NOT INITIAL.
          lv_hunk_cnt = lv_hunk_cnt + 1.
          IF lv_hunk_cnt = ls_hunk-hunk_no.
            DATA(lv_kind2) = COND string(
              WHEN lt_del IS NOT INITIAL AND lt_ins IS NOT INITIAL THEN `changed`
              WHEN lt_ins IS NOT INITIAL                            THEN `added`
              ELSE                                                       `deleted` ).
            lv_hunk_code = |>>> start of { lv_kind2 } block for LLM| && lv_nl.
            LOOP AT lt_ins INTO DATA(ls_il2).
              lv_hunk_code = lv_hunk_code &&
                |+ { ls_il2-line } | && ` | ` &&
                |{ escape( val = ls_il2-text format = cl_abap_format=>e_html_text ) }| && lv_nl.
            ENDLOOP.
            LOOP AT lt_del INTO DATA(ls_dl2).
              lv_hunk_code = lv_hunk_code &&
                |- { ls_dl2-line } | && ` | ` &&
                |{ escape( val = ls_dl2-text format = cl_abap_format=>e_html_text ) }| && lv_nl.
            ENDLOOP.
            lv_hunk_code = lv_hunk_code && |&lt;&lt;&lt; end of { lv_kind2 } block for LLM| && lv_nl.
          ENDIF.
        ENDIF.
      ENDIF.

      " Build display name for header
      DATA(lv_disp) = COND string(
        WHEN ls_hunk-class_name IS NOT INITIAL AND ls_hunk-display_name IS NOT INITIAL
        THEN |{ ls_hunk-class_name }=>{ ls_hunk-display_name }|
        WHEN ls_hunk-display_name IS NOT INITIAL THEN ls_hunk-display_name
        ELSE CONV string( ls_hunk-obj_name ) ).

      lv_html = lv_html &&
        |<div class="hdr">| &&
        |{ escape( val = CONV string( ls_hunk-objtype ) format = cl_abap_format=>e_html_text ) }: | &&
        |{ escape( val = lv_disp format = cl_abap_format=>e_html_text ) }| &&
        | &nbsp;&#9656;&nbsp; Hunk #{ ls_hunk-hunk_no }| &&
        | &nbsp;<span style="color:#7f8c99;font-weight:normal">| &&
        |{ ls_hunk-change_kind } &bull; line { ls_hunk-start_line } &bull; { ls_hunk-change_count } change(s)| &&
        `</span></div>` &&
        |<pre>{ lv_hunk_code }</pre>|.
    ENDLOOP.

    lv_html = lv_html && `</body></html>`.
    result = lv_html.

  ENDMETHOD.


  METHOD get_hunk_thread.
    READ TABLE it_hunk_threads INTO result
      WITH TABLE KEY hunk_key = is_hunk-hunk_key.
    IF sy-subrc = 0.
      RETURN.
    ENDIF.

    LOOP AT it_hunk_threads INTO result
      WHERE objtype = is_hunk-objtype
        AND obj_name = is_hunk-obj_name
        AND hunk_no = is_hunk-hunk_no.
      RETURN.
    ENDLOOP.

    CLEAR result.
  ENDMETHOD.


  METHOD get_hunk_comment.
    DATA ls_thread TYPE zif_code_acr_types=>ty_hunk_thread.
    READ TABLE it_hunk_info INTO DATA(ls_hunk)
      WITH TABLE KEY hunk_key = iv_hunk_key.
    IF sy-subrc = 0.
      ls_thread = get_hunk_thread(
        is_hunk         = ls_hunk
        it_hunk_threads = it_hunk_threads ).
    ELSE.
      READ TABLE it_hunk_threads INTO ls_thread
        WITH TABLE KEY hunk_key = iv_hunk_key.
    ENDIF.
    CHECK ls_thread-messages IS NOT INITIAL.

    DATA(lv_idx) = lines( ls_thread-messages ).
    WHILE lv_idx > 0.
      READ TABLE ls_thread-messages INTO DATA(ls_msg) INDEX lv_idx.
      IF sy-subrc = 0
         AND ls_msg-author = 'AI_Assistant'
         AND ls_msg-text IS NOT INITIAL.
        result = ls_msg-text.
        RETURN.
      ENDIF.
      lv_idx = lv_idx - 1.
    ENDWHILE.
  ENDMETHOD.


  METHOD get_summary_key.
    result = |AI_SUMMARY~{ iv_objtype }~{ iv_objname }|.
  ENDMETHOD.


  METHOD get_hunk_scroll_anchor.
    result = |ai_comment_{ iv_hunk_key }|.
    TRANSLATE result USING '/_ ~_ _ '.
  ENDMETHOD.


  METHOD get_summary_scroll_anchor.
    result = |ai_summary_{ iv_objtype }_{ iv_objname }|.
    TRANSLATE result USING '/_ ~_ _ '.
  ENDMETHOD.


  METHOD render_summary_html.
    DATA(lv_key) = get_summary_key(
      iv_objtype = iv_objtype
      iv_objname = iv_objname ).
    READ TABLE it_hunk_threads INTO DATA(ls_thread)
      WITH TABLE KEY hunk_key = lv_key.
    IF sy-subrc <> 0.
      LOOP AT it_hunk_threads INTO ls_thread
        WHERE objtype = iv_objtype
          AND obj_name = iv_objname.
        IF ls_thread-hunk_key CP 'AI_SUMMARY~*'
           OR ls_thread-change_kind = 'AI_SUMMARY'.
          EXIT.
        ENDIF.
        CLEAR ls_thread.
      ENDLOOP.
    ENDIF.
    CHECK ls_thread-messages IS NOT INITIAL.

    DATA(lv_idx) = lines( ls_thread-messages ).
    WHILE lv_idx > 0.
      READ TABLE ls_thread-messages INTO DATA(ls_msg) INDEX lv_idx.
      IF sy-subrc = 0
         AND ls_msg-author = 'AI_SUMMARY'
         AND ls_msg-text IS NOT INITIAL.
        DATA(lv_text) = escape( val = ls_msg-text format = cl_abap_format=>e_html_text ).
        REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>newline IN lv_text WITH `<br>`.
        DATA(lv_created_at_txt) = zcl_code_acr_state=>format_timestamp( ls_msg-created_at ).
        result =
          |<div id="{ get_summary_scroll_anchor( iv_objtype = iv_objtype iv_objname = iv_objname ) }" class="comments" style="margin:12px 0 18px 0">| &&
          `<span class="meta">AI_SUMMARY / AI Summary / ` &&
          escape( val = lv_created_at_txt format = cl_abap_format=>e_html_text ) &&
          `</span>` &&
          `<div class="note" style="background:#f5f0ff;border-color:#c8b6e8;color:#5f3b8f">` &&
          lv_text &&
          `</div></div>`.
        RETURN.
      ENDIF.
      lv_idx = lv_idx - 1.
    ENDWHILE.
  ENDMETHOD.


  METHOD save_summary.
    CHECK iv_text IS NOT INITIAL.

    DATA(lv_key) = get_summary_key(
      iv_objtype = iv_objtype
      iv_objname = iv_objname ).
    DATA lv_msg_ts TYPE timestampl.
    GET TIME STAMP FIELD lv_msg_ts.

    READ TABLE ct_hunk_threads ASSIGNING FIELD-SYMBOL(<ls_thread>)
      WITH TABLE KEY hunk_key = lv_key.
    IF sy-subrc <> 0.
      READ TABLE it_hunk_info INTO DATA(ls_hunk_info)
        WITH KEY objtype = iv_objtype obj_name = iv_objname.
      INSERT VALUE zif_code_acr_types=>ty_hunk_thread(
        hunk_key     = lv_key
        objtype      = iv_objtype
        obj_name     = iv_objname
        class_name   = ls_hunk_info-class_name
        display_name = ls_hunk_info-display_name
        hunk_no      = 0
        start_line   = 0
        change_count = 0
        change_kind  = 'AI_SUMMARY' ) INTO TABLE ct_hunk_threads.
      READ TABLE ct_hunk_threads ASSIGNING <ls_thread>
        WITH TABLE KEY hunk_key = lv_key.
    ENDIF.

    IF <ls_thread> IS ASSIGNED.
      DELETE <ls_thread>-messages WHERE author = 'AI_SUMMARY'.
      APPEND VALUE zif_code_acr_types=>ty_decline_msg(
        author      = 'AI_SUMMARY'
        author_name = 'AI Summary'
        created_at  = lv_msg_ts
        is_decline  = abap_false
        text        = iv_text ) TO <ls_thread>-messages.
    ENDIF.
  ENDMETHOD.

ENDCLASS.
