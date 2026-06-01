class ZCL_CODE_HTML_GEN definition
  public
  FINAL
  create public .

public section.

  class-methods ANSWER_TO_HTML
    importing
      !I_ANSWER type STRING
      !I_SOURCE type STRING optional
    returning
      value(RV_HTML) type STRING .
  class-methods SOURCE_TO_HTML
    importing
      !I_SOURCE type STRING
      !I_TITLE type STRING
    returning
      value(RV_HTML) type STRING .
  class-methods BUILD_DIFF_HTML
    importing
      !I_OLD_CODE type STRING
      !I_NEW_CODE type STRING
      !I_OBJECT_TYPE type STRING optional
      !I_OBJECT_NAME type STRING optional
    exporting
      !E_HTML type STRING
      !E_BASE_HTML type STRING
      !E_DIFF_KEY type STRING
      !ET_HUNK_INFO type ZIF_AVE_ACR_TYPES=>TY_T_HUNK_INFO
      !ET_ACR_STATS type ZIF_AVE_ACR_TYPES=>TY_T_OBJ_STATS .
protected section.
private section.

  class-methods NORMALIZE_MARKDOWN
    importing
      !I_TEXT type STRING
    returning
      value(RV_TEXT) type STRING .
  class-methods RENDER_ABAP_BLOCKS
    importing
      !I_TEXT type STRING
    returning
      value(RV_TEXT) type STRING .
  class-methods SOURCE_BLOCK_TO_HTML
    importing
      !I_SOURCE type STRING
      !I_TITLE type STRING
    returning
      value(RV_HTML) type STRING .
  class-methods RENDER_MARKDOWN_TEXT
    importing
      !I_TEXT type STRING
    returning
      value(RV_HTML) type STRING .
  class-methods RENDER_INLINE_MARKDOWN
    importing
      !I_TEXT type STRING
    returning
      value(RV_HTML) type STRING .
  class-methods CODE_BLOCK_TO_HTML
    importing
      !I_CODE type STRING
    returning
      value(RV_HTML) type STRING .
  class-methods ESCAPE_HTML
    importing
      !I_TEXT type STRING
    returning
      value(RV_TEXT) type STRING .
ENDCLASS.



CLASS ZCL_CODE_HTML_GEN IMPLEMENTATION.


  method ANSWER_TO_HTML.

    DATA lv_text_upper TYPE string.

    lv_text_upper = i_answer.
    SHIFT lv_text_upper LEFT DELETING LEADING space.
    TRANSLATE lv_text_upper TO UPPER CASE.

    IF lv_text_upper CP '<!DOCTYPE HTML*'
    OR lv_text_upper CP '<!DOCTYPE*'
    OR lv_text_upper CP '<HTML*'.
      rv_html = i_answer.
    ELSE.
      DATA(lv_render_text) = render_abap_blocks( i_answer ).
      DATA(lv_source_html) = source_block_to_html(
        i_source = i_source
        i_title  = 'Source code from code_agent' ).

      rv_html = |<!doctype html><html><head><meta charset="utf-8">|
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
             && |.cd-error\{padding:1px 8px;white-space:pre;color:red;font-weight:bold;\}|
             && |</style></head><body><div class="answer">|
             && lv_render_text
             && lv_source_html
             && |</div></body></html>|.
    ENDIF.

  endmethod.


  method BUILD_DIFF_HTML.

    DATA lt_old TYPE abaptxt255_tab.
    DATA lt_new TYPE abaptxt255_tab.
    DATA lt_hunk_html TYPE string_table.
    DATA lt_blame TYPE zif_ave_popup_types=>ty_blame_map.
    DATA lv_hunk_count TYPE i.
    DATA lv_hunk_ins TYPE i.
    DATA lv_hunk_mod TYPE i.
    DATA lv_hunk_del TYPE i.
    DATA lv_author TYPE versuser.
    DATA ls_part TYPE zif_ave_popup_types=>ty_part_row.
    DATA lt_approved TYPE zif_ave_acr_types=>ty_approved.
    DATA lt_declined TYPE zif_ave_acr_types=>ty_approved.
    DATA lt_decline_notes TYPE zif_ave_acr_types=>ty_t_decline_notes.
    DATA lt_hunk_actions TYPE zif_ave_acr_types=>ty_t_hunk_actions.
    DATA lt_hunk_threads TYPE zif_ave_acr_types=>ty_t_hunk_threads.

    CLEAR: e_html,
           e_base_html,
           e_diff_key,
           et_hunk_info,
           et_acr_stats.

    SPLIT i_old_code AT cl_abap_char_utilities=>newline INTO TABLE lt_old.
    SPLIT i_new_code AT cl_abap_char_utilities=>newline INTO TABLE lt_new.

    DATA(lt_diff) = zcl_ave_popup_diff=>compute_diff(
      it_old = lt_old
      it_new = lt_new
      i_title = 'Computing AI code diff' ).

    lt_diff = zcl_ave_acr_hunk_html=>filter_moved_lines( it_diff = lt_diff ).

    e_html = zcl_ave_popup_html=>diff_to_html(
      it_diff       = lt_diff
      i_title       = 'AI Code Change'
      i_meta        = 'LLM proposal vs current SAP source'
      i_two_pane    = abap_false
      i_compact     = abap_false
      i_plain       = abap_false
      i_code_review = abap_true ).

    DATA(lv_hunk_full_html) = zcl_ave_popup_html=>diff_to_html(
      it_diff       = lt_diff
      i_title       = 'AI Code Change'
      i_meta        = 'LLM proposal vs current SAP source'
      i_two_pane    = abap_true
      i_compact     = abap_false
      i_plain       = abap_false
      i_code_review = abap_true ).

    lt_hunk_html = zcl_ave_acr_hunk_html=>collect_rows(
      it_diff        = lt_diff
      iv_full_html   = lv_hunk_full_html
      iv_title       = 'AI Code Change'
      iv_meta        = 'LLM proposal vs current SAP source'
      iv_two_pane    = abap_true
      iv_plain       = abap_false
      iv_ignore_case = abap_false
      iv_is_created  = abap_false ).

    lv_author = 'AI_AGENT'.
    ls_part-type = COND #( WHEN i_object_type IS NOT INITIAL THEN i_object_type ELSE 'PROG' ).
    ls_part-object_name = COND #( WHEN i_object_name IS NOT INITIAL THEN i_object_name ELSE 'AI_CODE_CHANGE' ).
    ls_part-name = ls_part-object_name.
    ls_part-display_name = |{ ls_part-type } { ls_part-object_name }|.

    zcl_ave_acr_hunk_info=>collect(
      EXPORTING
        is_part            = ls_part
        it_diff            = lt_diff
        it_hunk_html       = lt_hunk_html
        it_blame           = lt_blame
        iv_author          = lv_author
        iv_display_name    = ls_part-display_name
        iv_versno_new      = '00000'
        iv_versno_old      = '00000'
        iv_versno_new_text = 'LLM proposal'
        iv_versno_old_text = 'Current source'
        iv_is_created      = abap_false
      IMPORTING
        et_hunk_info       = et_hunk_info
        ev_hunk_count      = lv_hunk_count
        ev_hunk_ins        = lv_hunk_ins
        ev_hunk_mod        = lv_hunk_mod
        ev_hunk_del        = lv_hunk_del ).

    APPEND VALUE zif_ave_acr_types=>ty_obj_stats(
      objtype      = ls_part-type
      obj_name     = ls_part-object_name
      author       = lv_author
      author_name  = zcl_ave_popup_data=>get_user_name( lv_author )
      hunk_count   = lv_hunk_count
      hunk_ins     = lv_hunk_ins
      hunk_mod     = lv_hunk_mod
      hunk_del     = lv_hunk_del
      display_name = ls_part-display_name ) TO et_acr_stats.

    e_base_html = e_html.
    e_diff_key = |{ ls_part-type }~{ ls_part-object_name }|.

    zcl_ave_acr_hunk_renderer=>inject_approve_btn(
      EXPORTING
        iv_key           = e_diff_key
        it_hunk_info     = et_hunk_info
        it_approved      = lt_approved
        it_declined      = lt_declined
        it_decline_notes = lt_decline_notes
        it_hunk_actions  = lt_hunk_actions
        it_hunk_threads  = lt_hunk_threads
        iv_ai_enabled    = abap_true
      CHANGING
        cv_html          = e_html
        ct_acr_stats     = et_acr_stats ).

  endmethod.


  method CODE_BLOCK_TO_HTML.

    DATA lt_lines TYPE STANDARD TABLE OF string WITH NON-UNIQUE DEFAULT KEY.
    DATA lv_lno TYPE i.

    SPLIT i_code AT cl_abap_char_utilities=>newline INTO TABLE lt_lines.
    rv_html = |<table class="code_tbl"><tbody>|.

    LOOP AT lt_lines INTO DATA(lv_line).
      lv_lno = lv_lno + 1.
      DATA(lv_class) = COND string(
        WHEN lv_line CS 'was not found or cannot be read'
          THEN 'cd-error'
          ELSE 'cd' ).
      rv_html = rv_html
             && |<tr><td class="ln">{ lv_lno }</td>|
             && |<td class="{ lv_class }">{ escape_html( i_text = lv_line ) }</td></tr>|.
    ENDLOOP.

    rv_html = rv_html && |</tbody></table>|.

  endmethod.


  method ESCAPE_HTML.

    rv_text = i_text.
    REPLACE ALL OCCURRENCES OF '&' IN rv_text WITH '&amp;'.
    REPLACE ALL OCCURRENCES OF '<' IN rv_text WITH '&lt;'.
    REPLACE ALL OCCURRENCES OF '>' IN rv_text WITH '&gt;'.
    REPLACE ALL OCCURRENCES OF '"' IN rv_text WITH '&quot;'.

  endmethod.


  method NORMALIZE_MARKDOWN.

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

  endmethod.


  method RENDER_ABAP_BLOCKS.

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

  endmethod.


  method RENDER_INLINE_MARKDOWN.

    rv_html = escape_html( i_text ).
    REPLACE ALL OCCURRENCES OF REGEX '\*\*([^*]+)\*\*' IN rv_html WITH '<strong>$1</strong>'.
    REPLACE ALL OCCURRENCES OF REGEX '`([^`]+)`' IN rv_html WITH '<code>$1</code>'.

  endmethod.


  method RENDER_MARKDOWN_TEXT.

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

  endmethod.


  method SOURCE_BLOCK_TO_HTML.

    IF i_source IS INITIAL.
      RETURN.
    ENDIF.

    rv_html = cl_abap_char_utilities=>newline
           && |<div class="source_title">{ escape_html( i_title ) }</div>|
           && code_block_to_html( i_source ).

  endmethod.


  method SOURCE_TO_HTML.

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

  endmethod.
ENDCLASS.
