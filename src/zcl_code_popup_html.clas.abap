CLASS zcl_code_popup_html DEFINITION
  PUBLIC
  FINAL
  CREATE PRIVATE.

  PUBLIC SECTION.
    "! Type aliases from ZIF_CODE_POPUP_TYPES (defined there for standalone compatibility)
    TYPES ty_blame_entry TYPE zif_code_popup_types=>ty_blame_entry.
    TYPES ty_blame_map   TYPE zif_code_popup_types=>ty_blame_map.

    "! Format a source table as a stand-alone HTML page with line numbers.
    CLASS-METHODS source_to_html
      IMPORTING it_source     TYPE abaptxt255_tab
                i_title       TYPE string
                i_meta        TYPE string OPTIONAL
      RETURNING VALUE(rv_html) TYPE string.

    "! Render a diff (from ZCL_CODE_POPUP_DIFF) as an HTML page.
    CLASS-METHODS diff_to_html
      IMPORTING it_diff           TYPE zif_code_popup_types=>ty_t_diff
                i_title           TYPE string
                i_meta            TYPE string OPTIONAL
                i_two_pane        TYPE abap_bool OPTIONAL
                i_compact         TYPE abap_bool OPTIONAL
                "! Skip char-level inline highlighting (huge-file mode).
                i_plain           TYPE abap_bool OPTIONAL
                i_ignore_case     TYPE abap_bool OPTIONAL
                i_start_line      TYPE i OPTIONAL
                it_blame          TYPE ty_blame_map OPTIONAL
                it_blame_deleted  TYPE ty_blame_map OPTIONAL
                i_code_review     TYPE abap_bool OPTIONAL
      RETURNING VALUE(result)     TYPE string.

    "! Format a CDS/DDL source as HTML with syntax highlighting.
    CLASS-METHODS cds_source_to_html
      IMPORTING it_source      TYPE abaptxt255_tab
                i_title        TYPE string
                i_meta         TYPE string OPTIONAL
      RETURNING VALUE(rv_html) TYPE string.

    "! Debug rendering of diff ops and pairing decisions.
    CLASS-METHODS debug_diff_html
      IMPORTING it_diff       TYPE zif_code_popup_types=>ty_t_diff
                i_title       TYPE string
                i_meta        TYPE string OPTIONAL
      RETURNING VALUE(result) TYPE string.

    "! Last source line number being rendered — updated during diff_to_html/debug_diff_html.
    "! Read this in a CATCH block to know which line caused a rendering error.
    CLASS-DATA gv_render_line TYPE i.

  PRIVATE SECTION.
    CLASS-METHODS is_comment
      IMPORTING iv_text        TYPE string
      RETURNING VALUE(rv_bool) TYPE abap_bool.
ENDCLASS.


CLASS zcl_code_popup_html IMPLEMENTATION.

  METHOD is_comment.
    DATA(lv_t) = condense( val = iv_text ).
    rv_bool = boolc( strlen( lv_t ) > 0 AND ( lv_t(1) = `"` OR lv_t(1) = `*` ) ).
  ENDMETHOD.

  METHOD source_to_html.
    DATA lv_rows TYPE string.
    DATA lv_lno  TYPE i.

    LOOP AT it_source INTO DATA(ls_src).
      lv_lno = lv_lno + 1.
      DATA(lv_line) = CONV string( ls_src ).
      REPLACE ALL OCCURRENCES OF `&` IN lv_line WITH `&amp;`.
      REPLACE ALL OCCURRENCES OF `<` IN lv_line WITH `&lt;`.
      REPLACE ALL OCCURRENCES OF `>` IN lv_line WITH `&gt;`.
      lv_rows = lv_rows &&
        |<tr><td class="ln">{ lv_lno }</td>| &&
        |<td class="cd">{ lv_line }</td></tr>|.
    ENDLOOP.

    rv_html =
      |<!DOCTYPE html><html><head><meta charset="utf-8"><style>| &&
      |*\{margin:0;padding:0;box-sizing:border-box\}| &&
      |body\{background:#ffffff;color:#1e1e1e;font:12px/1.5 Consolas,monospace\}| &&
      |.hdr\{background:#f3f3f3;padding:5px 12px;border-bottom:1px solid #ddd;| &&
             |color:#444;font-size:11px;display:flex;gap:16px;flex-wrap:wrap\}| &&
      |.ttl\{color:#0066aa;font-weight:bold\}| &&
      |.meta\{color:#888\}| &&
      |table\{border-collapse:collapse;width:100%\}| &&
      |tr:hover td\{background:#f0f4fa\}| &&
      |.ln\{color:#aaa;text-align:right;padding:1px 10px 1px 5px;| &&
           |user-select:none;min-width:42px;border-right:1px solid #e0e0e0;| &&
           |white-space:nowrap;background:#fafafa\}| &&
      |.cd\{padding:1px 8px;white-space:pre\}| &&
      |</style></head><body>| &&
      |<div class="hdr">| &&
      |<span class="ttl">| && i_title && |</span>| &&
      |<span class="meta">| && i_meta  && |</span>| &&
      |</div>| &&
      |<table><tbody>| && lv_rows &&
      |</tbody></table></body></html>|.
  ENDMETHOD.


  METHOD diff_to_html.
    DATA lv_rows  TYPE string.
    DATA lv_lno   TYPE i.
    DATA(lv_start_line) = COND i( WHEN i_start_line > 0 THEN i_start_line ELSE 1 ).
    lv_lno = lv_start_line - 1.

    " Pre-compute which '=' lines to show in compact mode (within 3 of any change)
    CONSTANTS lc_ctx TYPE i VALUE 3.
    DATA lt_show TYPE TABLE OF abap_bool WITH DEFAULT KEY.
    DATA(lv_ntot) = lines( it_diff ).
    DO lv_ntot TIMES. APPEND abap_false TO lt_show. ENDDO.
    IF i_compact = abap_true.
      DATA lv_ci TYPE i.
      lv_ci = 1.
      LOOP AT it_diff INTO DATA(ls_cm).
        IF ls_cm-op = '-' OR ls_cm-op = '+'.
          DATA lv_from TYPE i.
          DATA lv_to   TYPE i.
          lv_from = lv_ci - lc_ctx.
          lv_to   = lv_ci + lc_ctx.
          IF lv_from < 1. lv_from = 1. ENDIF.
          IF lv_to > lv_ntot. lv_to = lv_ntot. ENDIF.
          DATA lv_fi TYPE i.
          lv_fi = lv_from.
          WHILE lv_fi <= lv_to.
            lt_show[ lv_fi ] = abap_true.
            lv_fi = lv_fi + 1.
          ENDWHILE.
        ENDIF.
        lv_ci = lv_ci + 1.
      ENDLOOP.
    ENDIF.

    DATA(lo_progress) = NEW zcl_code_progress(
      i_title = 'Rendering diff' i_threshold_secs = 15 ).

    IF i_two_pane = abap_true.
      " ── Two-pane rendering ──────────────────────────────────────
      DATA lv_lno_l TYPE i.
      DATA lv_lno_r TYPE i.
      DATA lv_max_w TYPE i.
      DATA lv_pos2  TYPE i VALUE 1.
      DATA lv_tot2  TYPE i.
      lv_lno_l = lv_start_line - 1.
      lv_lno_r = lv_start_line - 1.
      lv_tot2 = lines( it_diff ).

      " Calculate max line length of left (base/new) content for column width
      LOOP AT it_diff INTO DATA(ls_w) WHERE op = '=' OR op = '+'.
        DATA(lv_wl) = strlen( condense( val = CONV string( ls_w-text ) ) ).
        IF lv_wl > lv_max_w. lv_max_w = lv_wl. ENDIF.
      ENDLOOP.
      lv_max_w = lv_max_w + 4.   " small padding

      DATA lv_gap2    TYPE abap_bool.
      DATA lv_acr_n2  TYPE i.        " code-review hunk counter (two-pane)
      WHILE lv_pos2 <= lv_tot2.
        IF lo_progress->check(
             i_remaining = lv_tot2 - lv_pos2 + 1
             i_total     = lv_tot2 ) = abap_true.
          EXIT.
        ENDIF.
        READ TABLE it_diff INTO DATA(ls_c2) INDEX lv_pos2.

        IF ls_c2-op = '='.
          lv_lno_l = lv_lno_l + 1. lv_lno_r = lv_lno_r + 1.
          IF i_compact = abap_true AND lt_show[ lv_pos2 ] = abap_false.
            IF lv_gap2 = abap_false.
              lv_rows = lv_rows &&
                |<tr style="background:#f0f0f0;color:#888">| &&
                |<td class="ln">...</td><td class="cd">...</td>| &&
                |<td class="sep"></td>| &&
                |<td class="ln">...</td><td class="cd">...</td></tr>|.
              lv_gap2 = abap_true.
            ENDIF.
            lv_pos2 = lv_pos2 + 1.
            CONTINUE.
          ENDIF.
          CLEAR lv_gap2.
          DATA(lv_eq2) = ls_c2-text.
          REPLACE ALL OCCURRENCES OF `&` IN lv_eq2 WITH `&amp;`.
          REPLACE ALL OCCURRENCES OF `<` IN lv_eq2 WITH `&lt;`.
          REPLACE ALL OCCURRENCES OF `>` IN lv_eq2 WITH `&gt;`.
          DATA(lv_cmt_eq2) = COND string( WHEN is_comment( ls_c2-text ) = abap_true
            THEN ` style="color:#999"` ELSE `` ).
          lv_rows = lv_rows &&
            |<tr><td class="ln">{ lv_lno_l }</td>| &&
            |<td class="cd"{ lv_cmt_eq2 }>{ lv_eq2 }</td>| &&
            |<td class="sep"></td>| &&
            |<td class="ln">{ lv_lno_r }</td>| &&
            |<td class="cd"{ lv_cmt_eq2 }>{ lv_eq2 }</td></tr>|.
          lv_pos2 = lv_pos2 + 1.

        ELSEIF ls_c2-op = '-' OR ls_c2-op = '+'.
          DATA lt_d2 TYPE string_table.
          DATA lt_i2 TYPE string_table.
          DATA lv_sc TYPE i.
          lv_sc = lv_pos2.
          WHILE lv_sc <= lv_tot2.
            READ TABLE it_diff INTO DATA(ls_s2) INDEX lv_sc.
            IF ls_s2-op = '-'. APPEND ls_s2-text TO lt_d2. lv_sc = lv_sc + 1.
            ELSEIF ls_s2-op = '+'. APPEND ls_s2-text TO lt_i2. lv_sc = lv_sc + 1.
            ELSEIF ls_s2-op = '=' AND condense( val = ls_s2-text ) = ``.
              DATA lv_peek2  TYPE i.
              DATA lv_extra2 TYPE i.
              DATA lv_more2  TYPE abap_bool.
              lv_peek2 = lv_sc + 1.
              lv_extra2 = 0.
              lv_more2 = abap_false.
              WHILE lv_peek2 <= lv_tot2.
                READ TABLE it_diff INTO DATA(ls_p2) INDEX lv_peek2.
                IF ls_p2-op = '-' OR ls_p2-op = '+'.
                  lv_more2 = abap_true.
                  EXIT.
                ELSEIF ls_p2-op = '=' AND condense( val = ls_p2-text ) = `` AND lv_extra2 < 1.
                  lv_extra2 = lv_extra2 + 1.
                  lv_peek2 = lv_peek2 + 1.
                  CONTINUE.
                ELSE.
                  EXIT.
                ENDIF.
              ENDWHILE.
              IF lv_more2 = abap_true.
                lv_sc = lv_sc + 1.
              ELSE.
                EXIT.
              ENDIF.
            ELSE. EXIT.
            ENDIF.
          ENDWHILE.
          DATA(lv_nd) = lines( lt_d2 ).
          DATA(lv_ni) = lines( lt_i2 ).

          " Blame separator for two-pane (added lines)
          IF lt_i2 IS NOT INITIAL.
            DATA lv_acr_marker2 TYPE string.
            CLEAR lv_acr_marker2.
            IF i_code_review = abap_true.
              lv_acr_n2 = lv_acr_n2 + 1.
              lv_acr_marker2 = |<!--ACR_{ lv_acr_n2 }-->|.
            ENDIF.
            IF it_blame IS NOT INITIAL.
              READ TABLE it_blame INTO DATA(ls_bl2) WITH KEY text = lt_i2[ 1 ].
              IF sy-subrc = 0.
                DATA(lv_bdate2)   = |{ ls_bl2-datum+6(2) }.{ ls_bl2-datum+4(2) }.{ ls_bl2-datum(4) }|.
                DATA(lv_btime2)   = |{ ls_bl2-zeit(2) }:{ ls_bl2-zeit+2(2) }|.
                DATA(lv_btask2)   = COND string(
                  WHEN ls_bl2-korrnum IS NOT INITIAL AND ls_bl2-task IS NOT INITIAL THEN | { ls_bl2-korrnum }/{ ls_bl2-task }|
                  WHEN ls_bl2-korrnum IS NOT INITIAL THEN | { ls_bl2-korrnum }|
                  WHEN ls_bl2-task IS NOT INITIAL THEN | { ls_bl2-task }|
                  ELSE `` ).
                DATA(lv_btasktxt2) = COND string( WHEN ls_bl2-task_text IS NOT INITIAL THEN | { ls_bl2-task_text }| ELSE `` ).
                DATA(lv_bauth2)   = |<b style="color:#0066aa">{ ls_bl2-author }| &&
                  COND string( WHEN ls_bl2-author_name IS NOT INITIAL THEN | ({ ls_bl2-author_name })| ELSE `` ) &&
                  `</b>`.
                DATA(lv_bverb2)   = COND string( WHEN lv_nd = 0 THEN 'inserted' ELSE 'changed' ).
                DATA(lv_bline2)   = |── { lv_bauth2 } { lv_bverb2 }  { lv_bdate2 }| &&
                  | { lv_btime2 }  v.{ ls_bl2-versno_text }{ lv_btask2 }{ lv_btasktxt2 } ──|.
                DATA(lv_bline2s)  = |── { lv_bauth2 } { lv_bverb2 }  { lv_bdate2 }| &&
                  | { lv_btime2 }  v.{ ls_bl2-versno_text } ──|.
                IF strlen( ls_bl2-task_text ) > 10.
                  lv_rows = lv_rows &&
                    |<tr style="background:#e8f4e8;color:#555;font-size:10px;font-style:italic">| &&
                    |<td class="ln">▶</td><td class="cd" colspan="3">{ lv_bline2s }{ lv_acr_marker2 }</td>| &&
                    |<td class="ln"></td><td class="cd"></td></tr>| &&
                    |<tr style="background:#e8f4e8;color:#555;font-size:10px;font-style:italic">| &&
                    |<td class="ln"></td><td class="cd" colspan="3">──{ lv_btask2 }{ lv_btasktxt2 } ──</td>| &&
                    |<td class="ln"></td><td class="cd"></td></tr>|.
                ELSE.
                  lv_rows = lv_rows &&
                    |<tr style="background:#e8f4e8;color:#555;font-size:10px;font-style:italic">| &&
                    |<td class="ln">▶</td><td class="cd" colspan="3">{ lv_bline2 }{ lv_acr_marker2 }</td>| &&
                    |<td class="ln"></td><td class="cd"></td></tr>|.
                ENDIF.
              ELSEIF i_code_review = abap_true.
                lv_rows = lv_rows &&
                  |<tr style="background:#e8f4e8;color:#555;font-size:10px;font-style:italic">| &&
                  |<td class="ln">▶</td><td class="cd" colspan="3">── { COND string( WHEN lv_nd = 0 THEN 'inserted' ELSE 'changed' ) } ──{ lv_acr_marker2 }</td>| &&
                  |<td class="ln"></td><td class="cd"></td></tr>|.
              ENDIF.
            ELSEIF i_code_review = abap_true.
              lv_rows = lv_rows &&
                |<tr style="background:#e8f4e8;color:#555;font-size:10px;font-style:italic">| &&
                |<td class="ln">▶</td><td class="cd" colspan="3">── { COND string( WHEN lv_nd = 0 THEN 'inserted' ELSE 'changed' ) } ──{ lv_acr_marker2 }</td>| &&
                |<td class="ln"></td><td class="cd"></td></tr>|.
            ENDIF.
          ENDIF.

          " Blame separator for two-pane (deleted lines)
          IF lt_d2 IS NOT INITIAL AND lt_i2 IS INITIAL.
            IF it_blame_deleted IS NOT INITIAL.
              READ TABLE it_blame_deleted INTO DATA(ls_bld2) WITH KEY text = lt_d2[ 1 ].
              IF sy-subrc = 0.
                DATA(lv_bddate2)   = |{ ls_bld2-datum+6(2) }.{ ls_bld2-datum+4(2) }.{ ls_bld2-datum(4) }|.
                DATA(lv_bdtime2)   = |{ ls_bld2-zeit(2) }:{ ls_bld2-zeit+2(2) }|.
                DATA(lv_bdtask2)   = COND string(
                  WHEN ls_bld2-korrnum IS NOT INITIAL AND ls_bld2-task IS NOT INITIAL THEN | { ls_bld2-korrnum }/{ ls_bld2-task }|
                  WHEN ls_bld2-korrnum IS NOT INITIAL THEN | { ls_bld2-korrnum }|
                  WHEN ls_bld2-task IS NOT INITIAL THEN | { ls_bld2-task }|
                  ELSE `` ).
                DATA(lv_bdtasktxt2) = COND string( WHEN ls_bld2-task_text IS NOT INITIAL THEN | { ls_bld2-task_text }| ELSE `` ).
                DATA(lv_bdauth2)   = |<b style="color:#0066aa">{ ls_bld2-author }| &&
                  COND string( WHEN ls_bld2-author_name IS NOT INITIAL THEN | ({ ls_bld2-author_name })| ELSE `` ) &&
                  `</b>`.
                DATA(lv_bdline2)   = |── { lv_bdauth2 } deleted  { lv_bddate2 } { lv_bdtime2 }  v.{ ls_bld2-versno_text }{ lv_bdtask2 }{ lv_bdtasktxt2 } ──|.
                IF strlen( lv_bdline2 ) > lv_max_w AND ( lv_bdtask2 IS NOT INITIAL OR lv_bdtasktxt2 IS NOT INITIAL ).
                  lv_rows = lv_rows &&
                    |<tr style="background:#fdf0f0;color:#555;font-size:10px;font-style:italic;font-weight:bold">| &&
                    |<td class="ln">◀</td><td class="cd" colspan="3">── { lv_bdauth2 } deleted  { lv_bddate2 } { lv_bdtime2 }  v.{ ls_bld2-versno_text } ──</td>| &&
                    |<td class="ln"></td><td class="cd"></td></tr>| &&
                    |<tr style="background:#fdf0f0;color:#555;font-size:10px;font-style:italic;font-weight:bold">| &&
                    |<td class="ln"></td><td class="cd" colspan="3">──{ lv_bdtask2 }{ lv_bdtasktxt2 } ──</td>| &&
                    |<td class="ln"></td><td class="cd"></td></tr>|.
                ELSE.
                  lv_rows = lv_rows &&
                    |<tr style="background:#fdf0f0;color:#555;font-size:10px;font-style:italic;font-weight:bold">| &&
                    |<td class="ln">◀</td><td class="cd" colspan="3">{ lv_bdline2 }</td>| &&
                    |<td class="ln"></td><td class="cd"></td></tr>|.
                ENDIF.
              ENDIF.
            ENDIF.
          ENDIF.

          DATA(lv_nd2) = lines( lt_d2 ).
          DATA(lv_ni2) = lines( lt_i2 ).

          DATA lt_d2_pair_idx TYPE zcl_code_popup_diff=>ty_t_int.
          DATA lt_i2_pair_idx TYPE zcl_code_popup_diff=>ty_t_int.

          " Shared pairing — identical alignment to the inline renderer.
          zcl_code_popup_diff=>pair_change_block(
            EXPORTING it_dels     = lt_d2
                      it_ins      = lt_i2
            IMPORTING et_del_pair = lt_d2_pair_idx
                      et_ins_pair = lt_i2_pair_idx ).

          DATA lv_dl2 TYPE string.
          DATA lv_il2 TYPE string.

          DATA lv_di TYPE i.
          DATA lv_ii TYPE i.
          DATA lv_pk TYPE i.
          lv_di = 1. lv_ii = 1. lv_pk = 1.
          DATA(lv_np) = lines( lt_d2_pair_idx ).
          WHILE lv_di <= lv_nd2 OR lv_ii <= lv_ni2.
            DATA(lv_npd) = COND i( WHEN lv_pk <= lv_np THEN lt_d2_pair_idx[ lv_pk ] ELSE lv_nd2 + 1 ).
            DATA(lv_npi) = COND i( WHEN lv_pk <= lv_np THEN lt_i2_pair_idx[ lv_pk ] ELSE lv_ni2 + 1 ).
            IF lv_di = lv_npd AND lv_ii = lv_npi.
              lv_lno_l = lv_lno_l + 1. lv_lno_r = lv_lno_r + 1.
              IF i_plain = abap_true.
                lv_dl2 = escape( val = lt_i2[ lv_ii ] format = cl_abap_format=>e_html_text ).
                lv_il2 = escape( val = lt_d2[ lv_di ] format = cl_abap_format=>e_html_text ).
              ELSE.
                lv_dl2 = zcl_code_popup_diff=>char_diff_html( iv_old = lt_d2[ lv_di ] iv_new = lt_i2[ lv_ii ] iv_side = 'N' iv_ignore_case = i_ignore_case ).
                lv_il2 = zcl_code_popup_diff=>char_diff_html( iv_old = lt_d2[ lv_di ] iv_new = lt_i2[ lv_ii ] iv_side = 'O' iv_ignore_case = i_ignore_case ).
              ENDIF.
              DATA(lv_cmt_l2) = COND string( WHEN is_comment( lt_i2[ lv_ii ] ) = abap_true
                THEN `;color:#999` ELSE `` ).
              DATA(lv_cmt_r2) = COND string( WHEN is_comment( lt_d2[ lv_di ] ) = abap_true
                THEN `;color:#999` ELSE `` ).
              lv_rows = lv_rows &&
                |<tr>| &&
                |<td class="ln" style="background:#eaffea">{ lv_lno_l }</td>| &&
                |<td class="cd" style="background:#eaffea{ lv_cmt_l2 }">{ lv_dl2 }</td>| &&
                |<td class="sep"></td>| &&
                |<td class="ln" style="background:#ffecec">{ lv_lno_r }</td>| &&
                |<td class="cd" style="background:#ffecec{ lv_cmt_r2 }">{ lv_il2 }</td></tr>|.
              CLEAR: lv_dl2, lv_il2.
              lv_di = lv_di + 1. lv_ii = lv_ii + 1. lv_pk = lv_pk + 1.
            ELSEIF lv_ii <= lv_ni2 AND lv_ii < lv_npi.
              lv_lno_l = lv_lno_l + 1.
              lv_dl2 = lt_i2[ lv_ii ].
              REPLACE ALL OCCURRENCES OF `&` IN lv_dl2 WITH `&amp;`.
              REPLACE ALL OCCURRENCES OF `<` IN lv_dl2 WITH `&lt;`.
              REPLACE ALL OCCURRENCES OF `>` IN lv_dl2 WITH `&gt;`.
              DATA(lv_cmt_si2) = COND string( WHEN is_comment( lt_i2[ lv_ii ] ) = abap_true
                THEN `;color:#999` ELSE `` ).
              lv_rows = lv_rows &&
                |<tr>| &&
                |<td class="ln" style="background:#eaffea">{ lv_lno_l }</td>| &&
                |<td class="cd" style="background:#eaffea{ lv_cmt_si2 }">{ lv_dl2 }</td>| &&
                |<td class="sep"></td>| &&
                |<td class="ln"></td><td class="cd"></td></tr>|.
              CLEAR lv_dl2.
              lv_ii = lv_ii + 1.
            ELSEIF lv_di <= lv_nd2.
              lv_lno_r = lv_lno_r + 1.
              lv_il2 = lt_d2[ lv_di ].
              REPLACE ALL OCCURRENCES OF `&` IN lv_il2 WITH `&amp;`.
              REPLACE ALL OCCURRENCES OF `<` IN lv_il2 WITH `&lt;`.
              REPLACE ALL OCCURRENCES OF `>` IN lv_il2 WITH `&gt;`.
              DATA(lv_cmt_sd2) = COND string( WHEN is_comment( lt_d2[ lv_di ] ) = abap_true
                THEN `;color:#999` ELSE `` ).
              lv_rows = lv_rows &&
                |<tr>| &&
                |<td class="ln"></td><td class="cd"></td>| &&
                |<td class="sep"></td>| &&
                |<td class="ln" style="background:#ffecec">{ lv_lno_r }</td>| &&
                |<td class="cd" style="background:#ffecec{ lv_cmt_sd2 }">{ lv_il2 }</td></tr>|.
              CLEAR lv_il2.
              lv_di = lv_di + 1.
            ELSE.
              lv_lno_l = lv_lno_l + 1.
              lv_dl2 = lt_i2[ lv_ii ].
              REPLACE ALL OCCURRENCES OF `&` IN lv_dl2 WITH `&amp;`.
              REPLACE ALL OCCURRENCES OF `<` IN lv_dl2 WITH `&lt;`.
              REPLACE ALL OCCURRENCES OF `>` IN lv_dl2 WITH `&gt;`.
              DATA(lv_cmt_rs2) = COND string( WHEN is_comment( lt_i2[ lv_ii ] ) = abap_true
                THEN `;color:#999` ELSE `` ).
              lv_rows = lv_rows &&
                |<tr>| &&
                |<td class="ln" style="background:#eaffea">{ lv_lno_l }</td>| &&
                |<td class="cd" style="background:#eaffea{ lv_cmt_rs2 }">{ lv_dl2 }</td>| &&
                |<td class="sep"></td>| &&
                |<td class="ln"></td><td class="cd"></td></tr>|.
              CLEAR lv_dl2.
              lv_ii = lv_ii + 1.
            ENDIF.
          ENDWHILE.

          CLEAR: lt_d2, lt_i2, lv_gap2, lt_d2_pair_idx, lt_i2_pair_idx.
          lv_pos2 = lv_sc.
        ELSE.
          lv_pos2 = lv_pos2 + 1.
        ENDIF.
      ENDWHILE.

      result =
        |<!DOCTYPE html><html><head><meta charset="utf-8"><style>| &&
        |*\{margin:0;padding:0;box-sizing:border-box\}| &&
        |body\{background:#fff;color:#1e1e1e;font:12px/1.5 Consolas,monospace\}| &&
        |.hdr\{background:#f3f3f3;padding:5px 56px;border-bottom:1px solid #ddd;| &&
               |color:#444;font-size:11px;display:flex;gap:8px;| &&
               |justify-content:center;align-items:center;flex-wrap:wrap\}| &&
        |.ttl\{color:#0066aa;font-weight:bold\}.meta\{color:#888\}| &&
        |table\{border-collapse:collapse;width:100%\}| &&
        |.ln\{color:#aaa;text-align:right;padding:1px 8px 1px 4px;| &&
             |user-select:none;min-width:36px;border-right:1px solid #e0e0e0;| &&
             |white-space:nowrap;background:#fafafa\}| &&
        |.cd\{padding:1px 8px;white-space:pre;width:{ lv_max_w }ch\}| &&
        |.sep\{border-left:2px solid #ccc;padding:0\}| &&
        |</style></head><body>| &&
        |<div class="hdr">| &&
        |<span class="ttl">| && i_title && |</span>| &&
        |<span class="meta">| && i_meta  && |</span>| &&
        |</div>| &&
        |<table><tbody>| && lv_rows &&
        |</tbody></table></body></html>|.
      RETURN.
    ENDIF.

    " ── Inline rendering (default) ───────────────────────────────
    DATA lv_pos   TYPE i VALUE 1.
    DATA lv_total TYPE i.
    DATA lv_acr_n TYPE i.   " code-review hunk counter
    lv_total = lines( it_diff ).

    DATA lv_gap_shown TYPE abap_bool.
    WHILE lv_pos <= lv_total.
      IF lo_progress->check(
           i_remaining = lv_total - lv_pos + 1
           i_total     = lv_total ) = abap_true.
        EXIT.
      ENDIF.
      READ TABLE it_diff INTO DATA(ls_cur) INDEX lv_pos.

      IF ls_cur-op = '='.
        lv_lno = lv_lno + 1.
        gv_render_line = lv_lno.
        IF i_compact = abap_true AND lt_show[ lv_pos ] = abap_false.
          IF lv_gap_shown = abap_false.
            lv_rows = lv_rows &&
              |<tr style="background:#f0f0f0;color:#888">| &&
              |<td class="ln">...</td><td class="cd">...</td></tr>|.
            lv_gap_shown = abap_true.
          ENDIF.
          lv_pos = lv_pos + 1.
          CONTINUE.
        ENDIF.
        CLEAR lv_gap_shown.
        DATA(lv_line_eq) = ls_cur-text.
        REPLACE ALL OCCURRENCES OF `&` IN lv_line_eq WITH `&amp;`.
        REPLACE ALL OCCURRENCES OF `<` IN lv_line_eq WITH `&lt;`.
        REPLACE ALL OCCURRENCES OF `>` IN lv_line_eq WITH `&gt;`.
        DATA(lv_cmt_eq) = COND string( WHEN is_comment( ls_cur-text ) = abap_true
          THEN ` style="color:#999"` ELSE `` ).
        lv_rows = lv_rows &&
          |<tr style="background:#ffffff">| &&
          |<td class="ln">{ lv_lno }</td>| &&
          |<td class="cd"{ lv_cmt_eq }>{ lv_line_eq }</td></tr>|.
        lv_pos = lv_pos + 1.

      ELSEIF ls_cur-op = '-' OR ls_cur-op = '+'.
        DATA lt_block   TYPE zif_code_popup_types=>ty_t_diff.
        DATA lt_dels    TYPE string_table.
        DATA lt_ins     TYPE string_table.
        DATA lt_del_idx TYPE STANDARD TABLE OF i WITH DEFAULT KEY.
        DATA lt_ins_idx TYPE STANDARD TABLE OF i WITH DEFAULT KEY.
        DATA lv_scan    TYPE i.
        CLEAR: lt_block, lt_dels, lt_ins, lt_del_idx, lt_ins_idx.
        lv_scan = lv_pos.

        WHILE lv_scan <= lv_total.
          READ TABLE it_diff INTO DATA(ls_s) INDEX lv_scan.
          IF ls_s-op = '-' OR ls_s-op = '+'.
            APPEND ls_s TO lt_block.
            lv_scan = lv_scan + 1.
          ELSEIF ls_s-op = '=' AND condense( val = ls_s-text ) = ``.
            DATA lv_peek         TYPE i.
            DATA lv_extra        TYPE i.
            DATA lv_more_changes TYPE abap_bool.
            lv_peek = lv_scan + 1.
            lv_extra = 0.
            lv_more_changes = abap_false.
            WHILE lv_peek <= lv_total.
              READ TABLE it_diff INTO DATA(ls_p) INDEX lv_peek.
              IF ls_p-op = '-' OR ls_p-op = '+'.
                lv_more_changes = abap_true.
                EXIT.
              ELSEIF ls_p-op = '=' AND condense( val = ls_p-text ) = `` AND lv_extra < 1.
                lv_extra = lv_extra + 1.
                lv_peek = lv_peek + 1.
                CONTINUE.
              ELSE.
                EXIT.
              ENDIF.
            ENDWHILE.
            IF lv_more_changes = abap_true.
              APPEND ls_s TO lt_block.
              lv_scan = lv_scan + 1.
            ELSE.
              EXIT.
            ENDIF.
          ELSE.
            EXIT.
          ENDIF.
        ENDWHILE.

        DATA lv_bi TYPE i.
        lv_bi = 1.
        WHILE lv_bi <= lines( lt_block ).
          DATA(ls_b) = lt_block[ lv_bi ].
          IF ls_b-op = '-' AND condense( val = ls_b-text ) <> ``.
            APPEND ls_b-text TO lt_dels.
            APPEND lv_bi     TO lt_del_idx.
          ELSEIF ls_b-op = '+' AND condense( val = ls_b-text ) <> ``.
            APPEND ls_b-text TO lt_ins.
            APPEND lv_bi     TO lt_ins_idx.
          ENDIF.
          lv_bi = lv_bi + 1.
        ENDWHILE.

        " ── Blame / code-review marker for added lines ──
        DATA lv_blame_ins_text TYPE string.
        CLEAR lv_blame_ins_text.
        LOOP AT lt_block INTO DATA(ls_blame_scan) WHERE op = '+'.
          IF condense( val = ls_blame_scan-text ) <> ``.
            lv_blame_ins_text = ls_blame_scan-text.
            EXIT.
          ENDIF.
        ENDLOOP.
        IF lv_blame_ins_text IS NOT INITIAL OR ( i_code_review = abap_true AND lt_ins IS NOT INITIAL ).
          " Increment ACR counter for every added hunk in code-review mode
          DATA lv_acr_marker TYPE string.
          CLEAR lv_acr_marker.
          IF i_code_review = abap_true AND lt_ins IS NOT INITIAL.
            lv_acr_n = lv_acr_n + 1.
            lv_acr_marker = |<!--ACR_{ lv_acr_n }-->|.
          ENDIF.

          IF it_blame IS NOT INITIAL AND lv_blame_ins_text IS NOT INITIAL.
            DATA ls_bl TYPE zif_code_popup_types=>ty_blame_entry.
            CLEAR ls_bl.
            LOOP AT it_blame INTO ls_bl
              WHERE text = lv_blame_ins_text
                 OR text = condense( val = lv_blame_ins_text ).
              EXIT.
            ENDLOOP.
            IF sy-subrc <> 0.
              " Fallback: line not in blame (existed before range) — take first blame entry with author
              LOOP AT it_blame INTO ls_bl WHERE author IS NOT INITIAL.
                EXIT.
              ENDLOOP.
            ENDIF.
            IF sy-subrc = 0.
              DATA(lv_bdate) = |{ ls_bl-datum+6(2) }.{ ls_bl-datum+4(2) }.{ ls_bl-datum(4) }|.
              DATA(lv_btime) = |{ ls_bl-zeit(2) }:{ ls_bl-zeit+2(2) }|.
              DATA(lv_btask) = COND string(
                WHEN ls_bl-korrnum IS NOT INITIAL AND ls_bl-task IS NOT INITIAL THEN | { ls_bl-korrnum }/{ ls_bl-task }|
                WHEN ls_bl-korrnum IS NOT INITIAL THEN | { ls_bl-korrnum }|
                WHEN ls_bl-task IS NOT INITIAL THEN | { ls_bl-task }|
                ELSE `` ).
              DATA(lv_btasktxt) = COND string( WHEN ls_bl-task_text IS NOT INITIAL THEN | { ls_bl-task_text }| ELSE `` ).
              lv_rows = lv_rows &&
                |<tr style="background:#e8f4e8;color:#555;font-size:10px;font-style:italic">| &&
                |<td class="ln">▶</td>| &&
                |<td class="cd">── <b style="color:#0066aa">{ ls_bl-author }| &&
                COND string( WHEN ls_bl-author_name IS NOT INITIAL THEN | ({ ls_bl-author_name })| ELSE `` ) &&
                |</b> { COND string( WHEN lt_dels IS INITIAL THEN 'inserted' ELSE 'changed' ) }  { lv_bdate } { lv_btime }  v.{ ls_bl-versno_text }{ lv_btask }{ lv_btasktxt } ──| &&
                lv_acr_marker && |</td></tr>|.
            ELSEIF i_code_review = abap_true AND lt_ins IS NOT INITIAL.
              lv_rows = lv_rows &&
                |<tr style="background:#e8f4e8;color:#555;font-size:10px;font-style:italic">| &&
                |<td class="ln">▶</td>| &&
                |<td class="cd">── { COND string( WHEN lt_dels IS INITIAL THEN 'inserted' ELSE 'changed' ) } ──{ lv_acr_marker }</td></tr>|.
            ENDIF.
          ELSEIF i_code_review = abap_true AND lt_ins IS NOT INITIAL.
            lv_rows = lv_rows &&
              |<tr style="background:#e8f4e8;color:#555;font-size:10px;font-style:italic">| &&
              |<td class="ln">▶</td>| &&
              |<td class="cd">── { COND string( WHEN lt_dels IS INITIAL THEN 'inserted' ELSE 'changed' ) } ──{ lv_acr_marker }</td></tr>|.
          ENDIF.
        ENDIF.

        " ── Blame for deleted lines ──
        IF it_blame_deleted IS NOT INITIAL AND lt_dels IS NOT INITIAL AND lt_ins IS INITIAL.
          READ TABLE it_blame_deleted INTO DATA(ls_bld) WITH KEY text = lt_dels[ 1 ].
          IF sy-subrc = 0.
            DATA(lv_bddate) = |{ ls_bld-datum+6(2) }.{ ls_bld-datum+4(2) }.{ ls_bld-datum(4) }|.
            DATA(lv_bdtime) = |{ ls_bld-zeit(2) }:{ ls_bld-zeit+2(2) }|.
            DATA(lv_bdtask) = COND string(
              WHEN ls_bld-korrnum IS NOT INITIAL AND ls_bld-task IS NOT INITIAL THEN | { ls_bld-korrnum }/{ ls_bld-task }|
              WHEN ls_bld-korrnum IS NOT INITIAL THEN | { ls_bld-korrnum }|
              WHEN ls_bld-task IS NOT INITIAL THEN | { ls_bld-task }|
              ELSE `` ).
            DATA(lv_bdtasktxt) = COND string(
              WHEN ls_bld-task_text IS NOT INITIAL THEN | { ls_bld-task_text }|
              ELSE `` ).
            lv_rows = lv_rows &&
              |<tr style="background:#fdf0f0;color:#555;font-size:10px;font-style:italic;font-weight:bold">| &&
              |<td class="ln">◀</td>| &&
              |<td class="cd">── <b style="color:#0066aa">{ ls_bld-author }| &&
              COND string( WHEN ls_bld-author_name IS NOT INITIAL THEN | ({ ls_bld-author_name })| ELSE `` ) &&
              |</b> deleted  { lv_bddate } { lv_bdtime }  v.{ ls_bld-versno_text }| &&
              |{ lv_bdtask }{ lv_bdtasktxt } ──</td></tr>|.
          ENDIF.
        ELSEIF i_code_review = abap_true AND lt_dels IS NOT INITIAL AND lt_ins IS INITIAL.
          lv_rows = lv_rows &&
            `<tr style="background:#fdf0f0;color:#555;font-size:10px;font-style:italic;font-weight:bold">` &&
            `<td class="ln">◀</td>` &&
            `<td class="cd">── deleted ──</td></tr>`.
        ENDIF.

        DATA(lv_ndels) = lines( lt_dels ).
        DATA(lv_nins)  = lines( lt_ins ).

        DATA lt_status      TYPE STANDARD TABLE OF c WITH DEFAULT KEY.
        DATA lt_inline_html TYPE string_table.
        CLEAR: lt_status, lt_inline_html.
        DATA lv_init TYPE i.
        lv_init = 1.
        WHILE lv_init <= lines( lt_block ).
          APPEND ` ` TO lt_status.
          APPEND `` TO lt_inline_html.
          lv_init = lv_init + 1.
        ENDWHILE.

        IF i_plain = abap_false AND lv_ndels > 0 AND lv_nins > 0.
          DATA lt_pair_dk TYPE zcl_code_popup_diff=>ty_t_int.
          DATA lt_pair_ik TYPE zcl_code_popup_diff=>ty_t_int.

          " Shared pairing — identical alignment to the two-pane renderer.
          zcl_code_popup_diff=>pair_change_block(
            EXPORTING it_dels     = lt_dels
                      it_ins      = lt_ins
            IMPORTING et_del_pair = lt_pair_dk
                      et_ins_pair = lt_pair_ik ).

          " Matched pairs: collapse each pair into ONE row at the earlier
          " position, rendering old→new char-diff (so a commented-out line shows
          " once, with the added '***' highlighted — not duplicated as a bare
          " deletion above and a commented insertion below). The partner position
          " is marked 'C' and skipped. Trivial structural lines no longer pair,
          " so this no longer produces the old "zebra".
          lv_pk = 1.
          WHILE lv_pk <= lines( lt_pair_dk ).
            DATA(lv_dk) = lt_pair_dk[ lv_pk ].
            DATA(lv_ik) = lt_pair_ik[ lv_pk ].
            lv_di    = lt_del_idx[ lv_dk ].
            lv_ii    = lt_ins_idx[ lv_ik ].
            DATA(lv_first) = COND i( WHEN lv_di < lv_ii THEN lv_di ELSE lv_ii ).
            DATA(lv_other) = COND i( WHEN lv_di > lv_ii THEN lv_di ELSE lv_ii ).
            lt_status[ lv_first ] = 'P'.
            lt_status[ lv_other ] = 'C'.
            lt_inline_html[ lv_first ] = zcl_code_popup_diff=>char_diff_html(
              iv_old         = lt_dels[ lv_dk ]
              iv_new         = lt_ins[ lv_ik ]
              iv_side        = 'B'
              iv_ignore_case = i_ignore_case ).
            lv_pk = lv_pk + 1.
          ENDWHILE.
        ENDIF.

        DATA lv_rb TYPE i.
        lv_rb = 1.
        WHILE lv_rb <= lines( lt_block ).
          DATA(ls_bo) = lt_block[ lv_rb ].
          DATA(lv_st) = lt_status[ lv_rb ].
          DATA(lv_cmt_b) = COND string( WHEN is_comment( ls_bo-text ) = abap_true
            THEN `;color:#999` ELSE `` ).
          IF ls_bo-op = '='.
            lv_lno = lv_lno + 1.
            DATA(lv_eq) = ls_bo-text.
            REPLACE ALL OCCURRENCES OF `&` IN lv_eq WITH `&amp;`.
            REPLACE ALL OCCURRENCES OF `<` IN lv_eq WITH `&lt;`.
            REPLACE ALL OCCURRENCES OF `>` IN lv_eq WITH `&gt;`.
            lv_rows = lv_rows &&
              |<tr style="background:#ffffff">| &&
              |<td class="ln">{ lv_lno }</td>| &&
              |<td class="cd" style="background:#ffffff{ lv_cmt_b }">{ lv_eq }</td></tr>|.
          ELSEIF lv_st = 'C'.
            " consumed — already rendered collapsed at its partner row
          ELSEIF lv_st = 'P'.
            " collapsed paired row: old→new inline char-diff, counts as new line
            lv_lno = lv_lno + 1.
            lv_rows = lv_rows &&
              |<tr style="background:#ffffff">| &&
              |<td class="ln">{ lv_lno }</td>| &&
              |<td class="cd" style="background:#ffffff{ lv_cmt_b }">{ lt_inline_html[ lv_rb ] }</td></tr>|.
          ELSEIF ls_bo-op = '-'.
            DATA(lv_dl) = ls_bo-text.
            REPLACE ALL OCCURRENCES OF `&` IN lv_dl WITH `&amp;`.
            REPLACE ALL OCCURRENCES OF `<` IN lv_dl WITH `&lt;`.
            REPLACE ALL OCCURRENCES OF `>` IN lv_dl WITH `&gt;`.
            lv_rows = lv_rows &&
              |<tr style="background:#ffecec">| &&
              |<td class="ln" style="color:#cc0000">-</td>| &&
              |<td class="cd" style="color:#cc0000{ lv_cmt_b }">{ lv_dl }</td></tr>|.
          ELSE.
            " solo insertion
            lv_lno = lv_lno + 1.
            DATA(lv_il) = ls_bo-text.
            REPLACE ALL OCCURRENCES OF `&` IN lv_il WITH `&amp;`.
            REPLACE ALL OCCURRENCES OF `<` IN lv_il WITH `&lt;`.
            REPLACE ALL OCCURRENCES OF `>` IN lv_il WITH `&gt;`.
            lv_rows = lv_rows &&
              |<tr style="background:#eaffea">| &&
              |<td class="ln" style="color:#006600">{ lv_lno }</td>| &&
              |<td class="cd" style="color:#006600{ lv_cmt_b }">{ lv_il }</td></tr>|.
          ENDIF.
          lv_rb = lv_rb + 1.
        ENDWHILE.

        CLEAR lt_dels.
        CLEAR lt_ins.
        lv_pos = lv_scan.
      ELSE.
        lv_pos = lv_pos + 1.
      ENDIF.
    ENDWHILE.

    result =
      |<!DOCTYPE html><html><head><meta charset="utf-8"><style>| &&
      |*\{margin:0;padding:0;box-sizing:border-box\}| &&
      |body\{background:#ffffff;color:#1e1e1e;font:12px/1.5 Consolas,monospace\}| &&
      |.hdr\{background:#f3f3f3;padding:5px 56px;border-bottom:1px solid #ddd;| &&
             |color:#444;font-size:11px;display:flex;gap:8px;| &&
             |justify-content:center;align-items:center;flex-wrap:wrap\}| &&
      |.ttl\{color:#0066aa;font-weight:bold\}| &&
      |.meta\{color:#888\}| &&
      |table\{border-collapse:collapse;width:100%\}| &&
      |.ln\{color:#aaa;text-align:right;padding:1px 10px 1px 5px;| &&
           |user-select:none;min-width:42px;border-right:1px solid #e0e0e0;| &&
           |white-space:nowrap;background:#fafafa\}| &&
      |.cd\{padding:1px 8px;white-space:pre\}| &&
      |</style></head><body>| &&
      |<div class="hdr">| &&
      |<span class="ttl">| && i_title && |</span>| &&
      |<span class="meta">| && i_meta  && |</span>| &&
      |</div>| &&
      |<table><tbody>| && lv_rows &&
      |</tbody></table></body></html>|.
  ENDMETHOD.


  METHOD debug_diff_html.
    " Debug rendering: dump diff ops + change blocks + pairing decisions.
    " Mirrors AVEDiff.debugToHtml() in html_simulator/diff.js — same input
    " through both should produce structurally identical output.
    DATA lv_ops_rows TYPE string.
    DATA lv_blocks   TYPE string.
    DATA lv_idx      TYPE i.

    " ── Section 1: raw ops list ──
    lv_idx = 0.
    LOOP AT it_diff INTO DATA(ls_op).
      lv_idx = lv_idx + 1.
      DATA(lv_op_cls) = COND string(
        WHEN ls_op-op = '=' THEN `eq`
        WHEN ls_op-op = '-' THEN `del`
        ELSE `ins` ).
      DATA(lv_text_e) = ls_op-text.
      REPLACE ALL OCCURRENCES OF `&` IN lv_text_e WITH `&amp;`.
      REPLACE ALL OCCURRENCES OF `<` IN lv_text_e WITH `&lt;`.
      REPLACE ALL OCCURRENCES OF `>` IN lv_text_e WITH `&gt;`.
      DATA(lv_show)   = COND string(
        WHEN lv_text_e IS INITIAL THEN `<em>&lt;empty&gt;</em>`
        ELSE lv_text_e ).
      lv_ops_rows = lv_ops_rows &&
        |<tr class="{ lv_op_cls }"><td class="ln">{ lv_idx }</td>| &&
        |<td class="op">{ ls_op-op }</td><td class="cd">{ lv_show }</td></tr>|.
    ENDLOOP.

    " ── Section 2: walk change blocks, record pairing decisions ──
    DATA lv_pos      TYPE i VALUE 1.
    DATA lv_total    TYPE i.
    DATA lv_block_no TYPE i VALUE 0.
    lv_total = lines( it_diff ).

    " Section 2 only computes diagnostic metrics; never let a metric/substring
    " glitch abort the whole page — Section 1 (the raw ops list) must survive.
    TRY.
    WHILE lv_pos <= lv_total.
      READ TABLE it_diff INTO DATA(ls_cur) INDEX lv_pos.
      IF ls_cur-op = '='.
        lv_pos = lv_pos + 1.
        CONTINUE.
      ENDIF.

      DATA lt_dels    TYPE string_table.
      DATA lt_ins     TYPE string_table.
      DATA lv_bridged TYPE i.
      CLEAR: lt_dels, lt_ins, lv_bridged.
      DATA lv_scan TYPE i.
      lv_scan = lv_pos.
      WHILE lv_scan <= lv_total.
        READ TABLE it_diff INTO DATA(ls_s) INDEX lv_scan.
        IF ls_s-op = '-'.
          IF condense( val = ls_s-text ) <> ``.
            APPEND ls_s-text TO lt_dels.
          ENDIF.
          lv_scan = lv_scan + 1.
        ELSEIF ls_s-op = '+'.
          IF condense( val = ls_s-text ) <> ``.
            APPEND ls_s-text TO lt_ins.
          ENDIF.
          lv_scan = lv_scan + 1.
        ELSEIF ls_s-op = '=' AND condense( val = ls_s-text ) = ``.
          " Bridge short empty '=' if more changes follow (max 1 in a row)
          DATA lv_peek         TYPE i.
          DATA lv_extra        TYPE i.
          DATA lv_more_changes TYPE abap_bool.
          lv_peek = lv_scan + 1.
          lv_extra = 0.
          lv_more_changes = abap_false.
          WHILE lv_peek <= lv_total.
            READ TABLE it_diff INTO DATA(ls_p) INDEX lv_peek.
            IF ls_p-op = '-' OR ls_p-op = '+'.
              lv_more_changes = abap_true.
              EXIT.
            ELSEIF ls_p-op = '=' AND condense( val = ls_p-text ) = `` AND lv_extra < 1.
              lv_extra = lv_extra + 1.
              lv_peek = lv_peek + 1.
              CONTINUE.
            ELSE.
              EXIT.
            ENDIF.
          ENDWHILE.
          IF lv_more_changes = abap_true.
            lv_bridged = lv_bridged + 1.
            lv_scan = lv_scan + 1.
          ELSE.
            EXIT.
          ENDIF.
        ELSE.
          EXIT.
        ENDIF.
      ENDWHILE.

      lv_block_no = lv_block_no + 1.
      DATA(lv_nd) = lines( lt_dels ).
      DATA(lv_ni) = lines( lt_ins ).
      DATA(lv_block_end) = lv_scan - 1.

      DATA lt_pair_dk TYPE STANDARD TABLE OF i WITH DEFAULT KEY.
      DATA lt_pair_ik TYPE STANDARD TABLE OF i WITH DEFAULT KEY.
      DATA lt_d_paired TYPE TABLE OF abap_bool WITH DEFAULT KEY.
      DATA lt_i_paired TYPE TABLE OF abap_bool WITH DEFAULT KEY.
      DATA lt_dp_dbg   TYPE TABLE OF i.
      " Must clear all block-local tables — DATA declarations are method-scoped
      " so they accumulate across iterations of this WHILE loop.
      CLEAR: lt_pair_dk, lt_pair_ik, lt_d_paired, lt_i_paired, lt_dp_dbg.
      DO lv_nd TIMES. APPEND abap_false TO lt_d_paired. ENDDO.
      DO lv_ni TIMES. APPEND abap_false TO lt_i_paired. ENDDO.

      IF lv_nd > 0 AND lv_ni > 0.
        DATA(lv_cols_dbg) = lv_ni + 1.
        DATA(lv_rows_dbg) = lv_nd + 1.
        DATA(lv_size_dbg) = lv_rows_dbg * lv_cols_dbg.
        DO lv_size_dbg TIMES.
          APPEND 0 TO lt_dp_dbg.
        ENDDO.

        DATA lv_di_dbg TYPE i.
        DATA lv_ii_dbg TYPE i.
        lv_di_dbg = 1.
        WHILE lv_di_dbg <= lv_nd.
          lv_ii_dbg = 1.
          WHILE lv_ii_dbg <= lv_ni.
            DATA(lv_cell_dbg) = lv_di_dbg * lv_cols_dbg + lv_ii_dbg + 1.
            DATA(lv_hcc_dbg) = zcl_code_popup_diff=>has_common_chars(
              iv_a = lt_dels[ lv_di_dbg ]
              iv_b = lt_ins[ lv_ii_dbg ] ).
            IF lv_hcc_dbg = abap_true.
              DATA(lv_prev_dbg) = ( lv_di_dbg - 1 ) * lv_cols_dbg + ( lv_ii_dbg - 1 ) + 1.
              lt_dp_dbg[ lv_cell_dbg ] = lt_dp_dbg[ lv_prev_dbg ] + 1.
            ELSE.
              DATA(lv_up_dbg)   = ( lv_di_dbg - 1 ) * lv_cols_dbg + lv_ii_dbg + 1.
              DATA(lv_left_dbg) = lv_di_dbg * lv_cols_dbg + ( lv_ii_dbg - 1 ) + 1.
              lt_dp_dbg[ lv_cell_dbg ] = COND i(
                WHEN lt_dp_dbg[ lv_up_dbg ] >= lt_dp_dbg[ lv_left_dbg ] THEN lt_dp_dbg[ lv_up_dbg ]
                ELSE lt_dp_dbg[ lv_left_dbg ] ).
            ENDIF.
            lv_ii_dbg = lv_ii_dbg + 1.
          ENDWHILE.
          lv_di_dbg = lv_di_dbg + 1.
        ENDWHILE.

        lv_di_dbg = lv_nd.
        lv_ii_dbg = lv_ni.
        WHILE lv_di_dbg > 0 AND lv_ii_dbg > 0.
          IF zcl_code_popup_diff=>has_common_chars( iv_a = lt_dels[ lv_di_dbg ] iv_b = lt_ins[ lv_ii_dbg ] ) = abap_true.
            INSERT lv_di_dbg INTO lt_pair_dk INDEX 1.
            INSERT lv_ii_dbg INTO lt_pair_ik INDEX 1.
            lv_di_dbg = lv_di_dbg - 1.
            lv_ii_dbg = lv_ii_dbg - 1.
          ELSE.
            DATA(lv_up_bt_dbg)   = ( lv_di_dbg - 1 ) * lv_cols_dbg + lv_ii_dbg + 1.
            DATA(lv_left_bt_dbg) = lv_di_dbg * lv_cols_dbg + ( lv_ii_dbg - 1 ) + 1.
            IF lt_dp_dbg[ lv_up_bt_dbg ] >= lt_dp_dbg[ lv_left_bt_dbg ].
              lv_di_dbg = lv_di_dbg - 1.
            ELSE.
              lv_ii_dbg = lv_ii_dbg - 1.
            ENDIF.
          ENDIF.
        ENDWHILE.
      ENDIF.

      DATA lv_pair_rows TYPE string.
      CLEAR lv_pair_rows.
      DATA lv_k TYPE i.
      lv_k = 1.
      WHILE lv_k <= lines( lt_pair_dk ).
        DATA(lv_dk) = lt_pair_dk[ lv_k ].
        DATA(lv_ik) = lt_pair_ik[ lv_k ].
        lt_d_paired[ lv_dk ] = abap_true.
        lt_i_paired[ lv_ik ] = abap_true.

        DATA(lv_a) = lt_dels[ lv_dk ].
        DATA(lv_b) = lt_ins[ lv_ik ].

        DATA(lv_a_e) = lv_a.
        REPLACE ALL OCCURRENCES OF `&` IN lv_a_e WITH `&amp;`.
        REPLACE ALL OCCURRENCES OF `<` IN lv_a_e WITH `&lt;`.
        REPLACE ALL OCCURRENCES OF `>` IN lv_a_e WITH `&gt;`.
        DATA(lv_b_e) = lv_b.
        REPLACE ALL OCCURRENCES OF `&` IN lv_b_e WITH `&amp;`.
        REPLACE ALL OCCURRENCES OF `<` IN lv_b_e WITH `&lt;`.
        REPLACE ALL OCCURRENCES OF `>` IN lv_b_e WITH `&gt;`.
        DATA(lv_a_show) = COND string(
          WHEN lv_a_e IS INITIAL THEN `<em>&lt;empty&gt;</em>` ELSE lv_a_e ).
        DATA(lv_b_show) = COND string(
          WHEN lv_b_e IS INITIAL THEN `<em>&lt;empty&gt;</em>` ELSE lv_b_e ).
        DATA(lv_inline) = zcl_code_popup_diff=>char_diff_html( iv_old = lv_a iv_new = lv_b iv_side = 'B' ).

        " ── pairing metrics ──────────────────────────────────────────────────
        DATA lv_ta_m TYPE string.
        DATA lv_tb_m TYPE string.
        lv_ta_m = lv_a. lv_tb_m = lv_b.
        WHILE strlen( lv_ta_m ) > 0 AND substring( val = lv_ta_m off = 0 len = 1 ) = ` `.
          lv_ta_m = substring( val = lv_ta_m off = 1 len = strlen( lv_ta_m ) - 1 ).
        ENDWHILE.
        WHILE strlen( lv_ta_m ) > 0 AND substring( val = lv_ta_m off = strlen( lv_ta_m ) - 1 len = 1 ) = ` `.
          lv_ta_m = substring( val = lv_ta_m off = 0 len = strlen( lv_ta_m ) - 1 ).
        ENDWHILE.
        WHILE strlen( lv_tb_m ) > 0 AND substring( val = lv_tb_m off = 0 len = 1 ) = ` `.
          lv_tb_m = substring( val = lv_tb_m off = 1 len = strlen( lv_tb_m ) - 1 ).
        ENDWHILE.
        WHILE strlen( lv_tb_m ) > 0 AND substring( val = lv_tb_m off = strlen( lv_tb_m ) - 1 len = 1 ) = ` `.
          lv_tb_m = substring( val = lv_tb_m off = 0 len = strlen( lv_tb_m ) - 1 ).
        ENDWHILE.
        DATA(lv_la_m) = strlen( lv_ta_m ).
        DATA(lv_lb_m) = strlen( lv_tb_m ).
        DATA lv_cp_m TYPE i.
        lv_cp_m = 0.   " explicit reset — VALUE 0 only inits once, not per loop pass
        WHILE lv_cp_m < lv_la_m AND lv_cp_m < lv_lb_m.
          IF substring( val = lv_ta_m off = lv_cp_m len = 1 ) = substring( val = lv_tb_m off = lv_cp_m len = 1 ).
            lv_cp_m = lv_cp_m + 1.
          ELSE. EXIT.
          ENDIF.
        ENDWHILE.
        DATA lv_cs_m TYPE i.
        lv_cs_m = 0.   " explicit reset — see lv_cp_m note
        DATA(lv_la_rest_m) = lv_la_m - lv_cp_m.
        DATA(lv_lb_rest_m) = lv_lb_m - lv_cp_m.
        WHILE lv_cs_m < lv_la_rest_m AND lv_cs_m < lv_lb_rest_m.
          IF substring( val = lv_ta_m off = lv_la_m - 1 - lv_cs_m len = 1 ) =
             substring( val = lv_tb_m off = lv_lb_m - 1 - lv_cs_m len = 1 ).
            lv_cs_m = lv_cs_m + 1.
          ELSE. EXIT.
          ENDIF.
        ENDWHILE.
        DATA lv_mid_am TYPE string.
        DATA lv_mid_bm TYPE string.
        CLEAR: lv_mid_am, lv_mid_bm.   " DATA in loop is not auto-reset between passes
        DATA(lv_mid_la_m) = lv_la_m - lv_cp_m - lv_cs_m.
        DATA(lv_mid_lb_m) = lv_lb_m - lv_cp_m - lv_cs_m.
        IF lv_mid_la_m > 0. lv_mid_am = substring( val = lv_ta_m off = lv_cp_m len = lv_mid_la_m ). ENDIF.
        IF lv_mid_lb_m > 0. lv_mid_bm = substring( val = lv_tb_m off = lv_cp_m len = lv_mid_lb_m ). ENDIF.
        DATA(lv_runs_m)  = zcl_code_popup_diff=>count_edit_runs( iv_a = lv_mid_am iv_b = lv_mid_bm ).
        DATA(lv_min_m)   = nmin( val1 = lv_la_m val2 = lv_lb_m ).
        DATA(lv_ratio_m) = COND i( WHEN lv_min_m > 0 THEN lv_cp_m * 100 / lv_min_m ELSE 0 ).

        " Build annotated lines: prefix in blue, middle normal, suffix in green
        DATA lv_pfx_e TYPE string.
        DATA lv_sfx_e TYPE string.
        DATA lv_amid_e TYPE string.
        DATA lv_bmid_e TYPE string.
        CLEAR: lv_pfx_e, lv_sfx_e, lv_amid_e, lv_bmid_e.   " not auto-reset between loop passes
        IF lv_cp_m > 0. lv_pfx_e = substring( val = lv_ta_m off = 0 len = lv_cp_m ).
          REPLACE ALL OCCURRENCES OF `&` IN lv_pfx_e WITH `&amp;`.
          REPLACE ALL OCCURRENCES OF `<` IN lv_pfx_e WITH `&lt;`.
          REPLACE ALL OCCURRENCES OF `>` IN lv_pfx_e WITH `&gt;`.
        ENDIF.
        IF lv_cs_m > 0. lv_sfx_e = substring( val = lv_ta_m off = lv_la_m - lv_cs_m len = lv_cs_m ).
          REPLACE ALL OCCURRENCES OF `&` IN lv_sfx_e WITH `&amp;`.
          REPLACE ALL OCCURRENCES OF `<` IN lv_sfx_e WITH `&lt;`.
          REPLACE ALL OCCURRENCES OF `>` IN lv_sfx_e WITH `&gt;`.
        ENDIF.
        lv_amid_e = lv_mid_am. lv_bmid_e = lv_mid_bm.
        REPLACE ALL OCCURRENCES OF `&` IN lv_amid_e WITH `&amp;`.
        REPLACE ALL OCCURRENCES OF `<` IN lv_amid_e WITH `&lt;`.
        REPLACE ALL OCCURRENCES OF `>` IN lv_amid_e WITH `&gt;`.
        REPLACE ALL OCCURRENCES OF `&` IN lv_bmid_e WITH `&amp;`.
        REPLACE ALL OCCURRENCES OF `<` IN lv_bmid_e WITH `&lt;`.
        REPLACE ALL OCCURRENCES OF `>` IN lv_bmid_e WITH `&gt;`.
        DATA(lv_ann_a) = |<span style="color:#0055cc">{ lv_pfx_e }</span>{ lv_amid_e }<span style="color:#006600">{ lv_sfx_e }</span>|.
        DATA(lv_ann_b) = |<span style="color:#0055cc">{ lv_pfx_e }</span>{ lv_bmid_e }<span style="color:#006600">{ lv_sfx_e }</span>|.
        DATA(lv_metrics) = |cp={ lv_cp_m } cs={ lv_cs_m } ratio={ lv_ratio_m }% runs={ lv_runs_m }|.

        lv_pair_rows = lv_pair_rows &&
          |<tr><td class="ln">{ lv_dk }/{ lv_ik }</td>| &&
          |<td class="cd"><span class="del-tag">-</span> <code>{ lv_ann_a }</code></td>| &&
          |<td class="cd"><span class="ins-tag">+</span> <code>{ lv_ann_b }</code></td>| &&
          |<td><span class="ok">PAIR</span><br><small style="color:#888">{ lv_metrics }</small></td>| &&
          |<td class="cd">{ lv_inline }</td></tr>|.
        lv_k = lv_k + 1.
      ENDWHILE.

      DATA lv_leftover TYPE string.
      CLEAR lv_leftover.
      lv_k = 1.
      WHILE lv_k <= lv_nd.
        IF lt_d_paired[ lv_k ] = abap_false.
          DATA(lv_d_e) = lt_dels[ lv_k ].
          REPLACE ALL OCCURRENCES OF `&` IN lv_d_e WITH `&amp;`.
          REPLACE ALL OCCURRENCES OF `<` IN lv_d_e WITH `&lt;`.
          REPLACE ALL OCCURRENCES OF `>` IN lv_d_e WITH `&gt;`.
          DATA(lv_d_show) = COND string( WHEN lv_d_e IS INITIAL THEN `<em>&lt;empty&gt;</em>` ELSE lv_d_e ).
          lv_leftover = lv_leftover && |<div class="solo del">SOLO - <code>{ lv_d_show }</code></div>|.
        ENDIF.
        lv_k = lv_k + 1.
      ENDWHILE.
      lv_k = 1.
      WHILE lv_k <= lv_ni.
        IF lt_i_paired[ lv_k ] = abap_false.
          DATA(lv_i_e) = lt_ins[ lv_k ].
          REPLACE ALL OCCURRENCES OF `&` IN lv_i_e WITH `&amp;`.
          REPLACE ALL OCCURRENCES OF `<` IN lv_i_e WITH `&lt;`.
          REPLACE ALL OCCURRENCES OF `>` IN lv_i_e WITH `&gt;`.
          DATA(lv_i_show) = COND string( WHEN lv_i_e IS INITIAL THEN `<em>&lt;empty&gt;</em>` ELSE lv_i_e ).
          lv_leftover = lv_leftover && |<div class="solo ins">SOLO + <code>{ lv_i_show }</code></div>|.
        ENDIF.
        lv_k = lv_k + 1.
      ENDWHILE.

      DATA(lv_pair_section) = COND string(
        WHEN lv_pair_rows IS NOT INITIAL THEN
          |<table class="pair"><thead><tr><th>-/+</th><th>del</th><th>ins</th>| &&
          |<th>verdict</th><th>char-diff (if paired)</th></tr></thead>| &&
          |<tbody>| && lv_pair_rows && |</tbody></table>|
        ELSE `<div class="meta">(no del/ins pairs to test)</div>` ).
      DATA(lv_leftover_section) = COND string(
        WHEN lv_leftover IS NOT INITIAL THEN |<div class="leftover">{ lv_leftover }</div>|
        ELSE `` ).

      " ── All-combinations matrix (≤8 dels AND ≤8 ins to keep output manageable)
      DATA lv_matrix_section TYPE string.
      CLEAR lv_matrix_section.
      IF lv_nd > 0 AND lv_ni > 0 AND lv_nd <= 8 AND lv_ni <= 8.
        DATA lv_mx_rows TYPE string.
        CLEAR lv_mx_rows.
        DATA lv_di_mx TYPE i.
        DATA lv_ii_mx TYPE i.
        lv_di_mx = 1.
        WHILE lv_di_mx <= lv_nd.
          lv_ii_mx = 1.
          WHILE lv_ii_mx <= lv_ni.
            DATA(lv_sa) = lt_dels[ lv_di_mx ].
            DATA(lv_sb) = lt_ins[ lv_ii_mx ].
            DATA(lv_hcc) = zcl_code_popup_diff=>has_common_chars( iv_a = lv_sa iv_b = lv_sb ).
            " Trim for metrics
            DATA lv_ma TYPE string.
            DATA lv_mb TYPE string.
            lv_ma = lv_sa. lv_mb = lv_sb.
            WHILE strlen( lv_ma ) > 0 AND substring( val = lv_ma off = 0 len = 1 ) = ` `.
              lv_ma = substring( val = lv_ma off = 1 len = strlen( lv_ma ) - 1 ). ENDWHILE.
            WHILE strlen( lv_ma ) > 0 AND substring( val = lv_ma off = strlen( lv_ma ) - 1 len = 1 ) = ` `.
              lv_ma = substring( val = lv_ma off = 0 len = strlen( lv_ma ) - 1 ). ENDWHILE.
            WHILE strlen( lv_mb ) > 0 AND substring( val = lv_mb off = 0 len = 1 ) = ` `.
              lv_mb = substring( val = lv_mb off = 1 len = strlen( lv_mb ) - 1 ). ENDWHILE.
            WHILE strlen( lv_mb ) > 0 AND substring( val = lv_mb off = strlen( lv_mb ) - 1 len = 1 ) = ` `.
              lv_mb = substring( val = lv_mb off = 0 len = strlen( lv_mb ) - 1 ). ENDWHILE.
            DATA(lv_la_mx) = strlen( lv_ma ).
            DATA(lv_lb_mx) = strlen( lv_mb ).
            DATA lv_cp_mx TYPE i.
            lv_cp_mx = 0.   " explicit reset — VALUE 0 only inits once, not per loop pass
            WHILE lv_cp_mx < lv_la_mx AND lv_cp_mx < lv_lb_mx.
              IF substring( val = lv_ma off = lv_cp_mx len = 1 ) = substring( val = lv_mb off = lv_cp_mx len = 1 ).
                lv_cp_mx = lv_cp_mx + 1.
              ELSE. EXIT.
              ENDIF.
            ENDWHILE.
            DATA lv_cs_mx TYPE i.
            lv_cs_mx = 0.   " explicit reset — see lv_cp_mx note
            DATA(lv_la_rx) = lv_la_mx - lv_cp_mx.
            DATA(lv_lb_rx) = lv_lb_mx - lv_cp_mx.
            WHILE lv_cs_mx < lv_la_rx AND lv_cs_mx < lv_lb_rx.
              IF substring( val = lv_ma off = lv_la_mx - 1 - lv_cs_mx len = 1 ) =
                 substring( val = lv_mb off = lv_lb_mx - 1 - lv_cs_mx len = 1 ).
                lv_cs_mx = lv_cs_mx + 1.
              ELSE. EXIT.
              ENDIF.
            ENDWHILE.
            DATA lv_mid_amx TYPE string.
            DATA lv_mid_bmx TYPE string.
            CLEAR: lv_mid_amx, lv_mid_bmx.   " not auto-reset between loop passes
            DATA(lv_mla_mx) = lv_la_mx - lv_cp_mx - lv_cs_mx.
            DATA(lv_mlb_mx) = lv_lb_mx - lv_cp_mx - lv_cs_mx.
            IF lv_mla_mx > 0. lv_mid_amx = substring( val = lv_ma off = lv_cp_mx len = lv_mla_mx ). ENDIF.
            IF lv_mlb_mx > 0. lv_mid_bmx = substring( val = lv_mb off = lv_cp_mx len = lv_mlb_mx ). ENDIF.
            DATA(lv_runs_mx)  = zcl_code_popup_diff=>count_edit_runs( iv_a = lv_mid_amx iv_b = lv_mid_bmx ).
            DATA(lv_min_mx)   = nmin( val1 = lv_la_mx val2 = lv_lb_mx ).
            DATA(lv_ratio_mx) = COND i( WHEN lv_min_mx > 0 THEN lv_cp_mx * 100 / lv_min_mx ELSE 0 ).
            DATA(lv_verdict)  = COND string( WHEN lv_hcc = abap_true
              THEN `<span style="color:#006600;font-weight:bold">PAIR</span>`
              ELSE `<span style="color:#cc0000">SKIP</span>` ).
            DATA(lv_row_bg) = COND string( WHEN lv_hcc = abap_true THEN `#eaffea` ELSE `#fff8f8` ).
            lv_mx_rows = lv_mx_rows &&
              |<tr style="background:{ lv_row_bg }">| &&
              |<td class="ln">{ lv_di_mx }/{ lv_ii_mx }</td>| &&
              |<td>{ lv_verdict }</td>| &&
              |<td>cp={ lv_cp_mx }&nbsp;cs={ lv_cs_mx }&nbsp;ratio={ lv_ratio_mx }%&nbsp;runs={ lv_runs_mx }</td>| &&
              |</tr>|.
            lv_ii_mx = lv_ii_mx + 1.
          ENDWHILE.
          lv_di_mx = lv_di_mx + 1.
        ENDWHILE.
        lv_matrix_section =
          |<details style="margin-top:4px"><summary style="cursor:pointer;color:#555;font-size:11px">| &&
          |All { lv_nd }×{ lv_ni } combinations</summary>| &&
          |<table style="width:auto;margin-top:4px"><thead><tr>| &&
          |<th>d/i</th><th>verdict</th><th>metrics</th></tr></thead>| &&
          |<tbody>{ lv_mx_rows }</tbody></table></details>|.
      ENDIF.

      DATA(lv_bridge_note) = COND string(
        WHEN lv_bridged > 0 THEN | <span class="meta">— bridged { lv_bridged } empty '=' line(s)</span>|
        ELSE `` ).
      lv_blocks = lv_blocks &&
        |<div class="block"><h3>Block #{ lv_block_no } | &&
        |<span class="meta">({ lv_nd } dels, { lv_ni } ins, ops [{ lv_pos }..{ lv_block_end }])</span>| &&
        lv_bridge_note && |</h3>| &&
        lv_pair_section && lv_leftover_section && lv_matrix_section && |</div>|.

      lv_pos = lv_scan.
    ENDWHILE.
    CATCH cx_root INTO DATA(lx_dbg).
      lv_blocks = lv_blocks &&
        |<div class="block" style="color:#cc0000">Pairing diagnostics aborted: | &&
        |{ escape( val = lx_dbg->get_text( ) format = cl_abap_format=>e_html_text ) }</div>|.
    ENDTRY.

    IF lv_blocks IS INITIAL.
      lv_blocks = `<div class="meta">(no change blocks)</div>`.
    ENDIF.

    result =
      |<!DOCTYPE html><html><head><meta charset="utf-8"><style>| &&
      |*\{margin:0;padding:0;box-sizing:border-box\}| &&
      |body\{background:#fff;color:#222;font:12px/1.5 Segoe UI,sans-serif;padding:10px\}| &&
      |h2\{font-size:13px;margin:14px 0 6px;color:#0066aa;border-bottom:1px solid #ddd;padding-bottom:3px\}| &&
      |h3\{font-size:12px;margin:8px 0 4px;color:#444\}| &&
      |.hdr\{background:#f3f3f3;padding:6px 10px;border:1px solid #ddd;color:#444;| &&
            |display:flex;gap:14px;flex-wrap:wrap;margin-bottom:8px\}| &&
      |.ttl\{color:#0066aa;font-weight:bold\}.meta\{color:#888;font-weight:normal;font-size:11px\}| &&
      |table\{border-collapse:collapse;width:100%;font:11px/1.4 Consolas,monospace;margin-bottom:6px\}| &&
      |th,td\{padding:2px 6px;border:1px solid #e0e0e0;text-align:left;vertical-align:top\}| &&
      |th\{background:#fafafa;font-weight:600\}| &&
      |.ln\{color:#aaa;text-align:right;width:40px;background:#fafafa\}| &&
      |.op\{width:24px;text-align:center;font-weight:bold\}| &&
      |tr.eq td\{color:#888\}| &&
      |tr.del\{background:#ffecec\}tr.del td.op\{color:#cc0000\}| &&
      |tr.ins\{background:#eaffea\}tr.ins td.op\{color:#006600\}| &&
      |.cd\{white-space:pre;font:11px/1.4 Consolas,monospace\}| &&
      |code\{font:11px/1.4 Consolas,monospace;background:#f7f7f7;padding:1px 4px;border-radius:2px\}| &&
      |.block\{border:1px solid #ddd;padding:6px;margin-bottom:8px;border-radius:3px;background:#fcfcfc\}| &&
      |.pair th\{background:#eef\}| &&
      |.ok\{color:#006600;font-weight:bold\}.bad\{color:#cc0000;font-weight:bold\}| &&
      |.del-tag\{color:#cc0000;font-weight:bold\}.ins-tag\{color:#006600;font-weight:bold\}| &&
      |.solo\{margin:2px 0;padding:2px 6px;border-radius:2px;font:11px/1.4 Consolas,monospace\}| &&
      |.solo.del\{background:#ffecec;color:#cc0000\}| &&
      |.solo.ins\{background:#eaffea;color:#006600\}| &&
      |.leftover\{margin-top:4px\}| &&
      |em\{color:#aaa;font-style:italic\}| &&
      |</style></head><body>| &&
      |<div class="hdr"><span class="ttl">DEBUG: | && i_title && |</span>| &&
      |<span class="meta">| && i_meta && |</span></div>| &&
      |<h2>1. Diff ops ({ lv_total } total)</h2>| &&
      |<table><thead><tr><th>#</th><th>op</th><th>text</th></tr></thead>| &&
      |<tbody>| && lv_ops_rows && |</tbody></table>| &&
      |<h2>2. Change blocks &amp; pairing decisions</h2>| && lv_blocks &&
      |</body></html>|.
  ENDMETHOD.


  METHOD cds_source_to_html.
    " Helper: apply span tags by match positions (avoids regex backreference issues).
    " Processes matches from left to right and wraps each with <span class=css_class>.
    DATA: lv_rows TYPE string,
          lv_lno  TYPE i.

    DATA(lv_kw_regex) =
      '\b(define|view|entity|root|as|select|from|key|association|' &&
      'to|one|many|redirected|composition|join|left|outer|inner|cross|on|' &&
      'where|group|by|having|union|all|intersect|except|distinct|order|' &&
      'asc|desc|case|when|then|else|end|and|or|not|null|is|with|' &&
      'parameters|cast|coalesce|concat|upper|lower|substring|length|trim|' &&
      'projection|extend|abstract|transactional|query|interface|' &&
      'draft|enabled|annotate|aspect|type|of|in|between|like|exists|' &&
      'count|sum|avg|min|max|currency|unit|localized|literal|parent|' &&
      'provider|contract|strict|authorization|check)\b'.

    LOOP AT it_source INTO DATA(ls_src).
      lv_lno = lv_lno + 1.
      DATA(lv_line) = CONV string( ls_src ).

      REPLACE ALL OCCURRENCES OF `&` IN lv_line WITH `&amp;`.
      REPLACE ALL OCCURRENCES OF `<` IN lv_line WITH `&lt;`.
      REPLACE ALL OCCURRENCES OF `>` IN lv_line WITH `&gt;`.

      DATA(lv_trimmed) = condense( val = lv_line ).
      DATA(lv_tlen)    = strlen( lv_trimmed ).

      DATA lv_cell TYPE string.

      IF lv_tlen >= 2 AND lv_trimmed(2) = '//'.
        lv_cell = |<span class="cmt">{ lv_line }</span>|.
      ELSEIF lv_tlen >= 2 AND lv_trimmed(2) = '/*'.
        lv_cell = |<span class="cmt">{ lv_line }</span>|.
      ELSE.
        lv_cell = lv_line.

        " Highlight @Annotation names using position-based approach.
        DATA lt_ann TYPE match_result_tab.
        FIND ALL OCCURRENCES OF REGEX '@[\w.]+'
          IN lv_cell RESULTS lt_ann IGNORING CASE.
        IF lt_ann IS NOT INITIAL.
          DATA: lv_ann_out TYPE string,
                lv_ann_pos TYPE i.
          DATA: lv_ann_before TYPE i,
                lv_ann_len    TYPE i,
                lv_ann_off    TYPE i.
          LOOP AT lt_ann INTO DATA(ls_ann).
            lv_ann_off    = ls_ann-offset.
            lv_ann_before = lv_ann_off - lv_ann_pos.
            lv_ann_len    = ls_ann-length.
            lv_ann_out = lv_ann_out &&
              lv_cell+lv_ann_pos(lv_ann_before) &&
              |<span class="ann">{ lv_cell+lv_ann_off(lv_ann_len) }</span>|.
            lv_ann_pos = lv_ann_off + lv_ann_len.
          ENDLOOP.
          lv_cell = lv_ann_out && lv_cell+lv_ann_pos.
        ENDIF.

        " Highlight CDS keywords using position-based approach.
        DATA lt_kw TYPE match_result_tab.
        FIND ALL OCCURRENCES OF REGEX lv_kw_regex
          IN lv_cell RESULTS lt_kw IGNORING CASE.
        IF lt_kw IS NOT INITIAL.
          DATA: lv_kw_out TYPE string,
                lv_kw_pos TYPE i.
          DATA: lv_kw_before TYPE i,
                lv_kw_len    TYPE i,
                lv_kw_off    TYPE i.
          LOOP AT lt_kw INTO DATA(ls_kw).
            lv_kw_off    = ls_kw-offset.
            lv_kw_before = lv_kw_off - lv_kw_pos.
            lv_kw_len    = ls_kw-length.
            lv_kw_out = lv_kw_out &&
              lv_cell+lv_kw_pos(lv_kw_before) &&
              |<span class="kw">{ lv_cell+lv_kw_off(lv_kw_len) }</span>|.
            lv_kw_pos = lv_kw_off + lv_kw_len.
          ENDLOOP.
          lv_cell = lv_kw_out && lv_cell+lv_kw_pos.
        ENDIF.
      ENDIF.

      lv_rows = lv_rows &&
        |<tr><td class="ln">{ lv_lno }</td>| &&
        |<td class="cd">{ lv_cell }</td></tr>|.
    ENDLOOP.

    rv_html =
      |<!DOCTYPE html><html><head><meta charset="utf-8"><style>| &&
      |*\{margin:0;padding:0;box-sizing:border-box\}| &&
      |body\{background:#fff;color:#1e1e1e;font:12px/1.5 Consolas,monospace\}| &&
      |.hdr\{background:#f3f3f3;padding:5px 12px;border-bottom:1px solid #ddd;| &&
             |color:#444;font-size:11px;display:flex;gap:16px;flex-wrap:wrap\}| &&
      |.ttl\{color:#0066aa;font-weight:bold\}| &&
      |.meta\{color:#888\}| &&
      |table\{border-collapse:collapse;width:100%\}| &&
      |tr:hover td\{background:#f0f4fa\}| &&
      |.ln\{color:#aaa;text-align:right;padding:1px 10px 1px 5px;| &&
           |user-select:none;min-width:42px;border-right:1px solid #e0e0e0;| &&
           |white-space:nowrap;background:#fafafa\}| &&
      |.cd\{padding:1px 8px;white-space:pre\}| &&
      |.kw\{color:#0070c1;font-weight:bold\}| &&
      |.ann\{color:#267f99\}| &&
      |.cmt\{color:#008000\}| &&
      |</style></head><body>| &&
      |<div class="hdr">| &&
      |<span class="ttl">| && i_title && |</span>| &&
      |<span class="meta">| && i_meta  && |</span>| &&
      |</div>| &&
      |<table><tbody>| && lv_rows &&
      |</tbody></table></body></html>|.
  ENDMETHOD.

ENDCLASS.
