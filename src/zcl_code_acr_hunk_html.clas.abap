CLASS zcl_code_acr_hunk_html DEFINITION
  PUBLIC
  FINAL
  CREATE PRIVATE.

  PUBLIC SECTION.
    CLASS-METHODS collect_rows
      IMPORTING
        it_diff        TYPE zif_code_popup_types=>ty_t_diff
        iv_full_html   TYPE string
        iv_title       TYPE string
        iv_meta        TYPE string
        iv_two_pane    TYPE abap_bool
        iv_plain       TYPE abap_bool
        iv_ignore_case TYPE abap_bool
        iv_is_created  TYPE abap_bool
        iv_context     TYPE i DEFAULT 3
        it_blame         TYPE zif_code_popup_types=>ty_blame_map OPTIONAL
        it_blame_deleted TYPE zif_code_popup_types=>ty_blame_map OPTIONAL
      RETURNING
        VALUE(result)  TYPE string_table.

    CLASS-METHODS filter_moved_lines
      IMPORTING
        it_diff        TYPE zif_code_popup_types=>ty_t_diff
        iv_ignore_case TYPE abap_bool DEFAULT abap_false
      RETURNING
        VALUE(result)  TYPE zif_code_popup_types=>ty_t_diff.

  PRIVATE SECTION.
    CLASS-METHODS extract_rows
      IMPORTING
        iv_html        TYPE string
      RETURNING
        VALUE(result)  TYPE string.

    CLASS-METHODS normalize_moved_line
      IMPORTING
        iv_text        TYPE string
        iv_ignore_case TYPE abap_bool
      RETURNING
        VALUE(result)  TYPE string.

    CLASS-METHODS change_block_size
      IMPORTING
        it_diff        TYPE zif_code_popup_types=>ty_t_diff
        iv_index       TYPE i
      RETURNING
        VALUE(result)  TYPE i.
ENDCLASS.


CLASS zcl_code_acr_hunk_html IMPLEMENTATION.

  METHOD collect_rows.
    DATA(lv_rows_html) = extract_rows( iv_full_html ).
    IF iv_is_created = abap_true AND lv_rows_html IS NOT INITIAL.
      APPEND lv_rows_html TO result.
      RETURN.
    ENDIF.

    DATA lv_diff_pos TYPE i VALUE 1.
    DATA lv_hunk_render_line TYPE i VALUE 0.
    DATA(lv_diff_total) = lines( it_diff ).

    WHILE lv_diff_pos <= lv_diff_total.
      READ TABLE it_diff INTO DATA(ls_hscan_start) INDEX lv_diff_pos.
      IF ls_hscan_start-op <> '-' AND ls_hscan_start-op <> '+'.
        IF ls_hscan_start-op = '='.
          lv_hunk_render_line = lv_hunk_render_line + 1.
        ENDIF.
        lv_diff_pos = lv_diff_pos + 1.
        CONTINUE.
      ENDIF.

      DATA lt_hunk_diff TYPE zif_code_popup_types=>ty_t_diff.
      DATA lt_hunk_lines TYPE string_table.
      CLEAR: lt_hunk_diff, lt_hunk_lines.
      DATA(lv_hunk_render_start) = lv_hunk_render_line + 1.
      DATA(lv_hscan) = lv_diff_pos.

      WHILE lv_hscan <= lv_diff_total.
        READ TABLE it_diff INTO DATA(ls_hscan) INDEX lv_hscan.
        IF ls_hscan-op = '-' OR ls_hscan-op = '+'.
          APPEND ls_hscan TO lt_hunk_diff.
          APPEND CONV string( ls_hscan-text ) TO lt_hunk_lines.
          lv_hscan = lv_hscan + 1.
        ELSEIF ls_hscan-op = '=' AND condense( val = ls_hscan-text ) = ``.
          DATA(lv_hpeek) = lv_hscan + 1.
          DATA(lv_hextra) = 0.
          DATA(lv_hmore_changes) = abap_false.
          WHILE lv_hpeek <= lv_diff_total.
            READ TABLE it_diff INTO DATA(ls_hpeek) INDEX lv_hpeek.
            IF ls_hpeek-op = '-' OR ls_hpeek-op = '+'.
              lv_hmore_changes = abap_true.
              EXIT.
            ELSEIF ls_hpeek-op = '=' AND condense( val = ls_hpeek-text ) = `` AND lv_hextra < 1.
              lv_hextra = lv_hextra + 1.
              lv_hpeek = lv_hpeek + 1.
              CONTINUE.
            ELSE.
              EXIT.
            ENDIF.
          ENDWHILE.
          IF lv_hmore_changes = abap_true.
            APPEND ls_hscan TO lt_hunk_diff.
            lv_hscan = lv_hscan + 1.
          ELSE.
            EXIT.
          ENDIF.
        ELSE.
          EXIT.
        ENDIF.
      ENDWHILE.

      IF zcl_code_acr_stats=>is_blank_hunk( lt_hunk_lines ) = abap_false.
        DATA lt_render_diff TYPE zif_code_popup_types=>ty_t_diff.
        CLEAR lt_render_diff.
        DATA(lv_ctx_before) = 0.
        DATA(lv_ctx_scan) = lv_diff_pos - 1.
        WHILE lv_ctx_scan >= 1 AND lv_ctx_before < iv_context.
          READ TABLE it_diff INTO DATA(ls_ctx_before) INDEX lv_ctx_scan.
          IF sy-subrc <> 0 OR ls_ctx_before-op <> '='.
            EXIT.
          ENDIF.
          INSERT ls_ctx_before INTO lt_render_diff INDEX 1.
          lv_ctx_before = lv_ctx_before + 1.
          lv_ctx_scan = lv_ctx_scan - 1.
        ENDWHILE.

        INSERT LINES OF lt_hunk_diff INTO TABLE lt_render_diff.

        DATA(lv_ctx_after) = 0.
        lv_ctx_scan = lv_hscan.
        WHILE lv_ctx_scan <= lv_diff_total AND lv_ctx_after < iv_context.
          READ TABLE it_diff INTO DATA(ls_ctx_after) INDEX lv_ctx_scan.
          IF sy-subrc <> 0 OR ls_ctx_after-op <> '='.
            EXIT.
          ENDIF.
          APPEND ls_ctx_after TO lt_render_diff.
          lv_ctx_after = lv_ctx_after + 1.
          lv_ctx_scan = lv_ctx_scan + 1.
        ENDWHILE.

        lv_hunk_render_start = lv_hunk_render_line - lv_ctx_before + 1.
        IF lv_hunk_render_start < 1.
          lv_hunk_render_start = 1.
        ENDIF.
        DATA(lv_hunk_full_html) = zcl_code_popup_html=>diff_to_html(
          it_diff       = lt_render_diff
          i_title       = iv_title
          i_meta        = iv_meta
          i_two_pane    = iv_two_pane
          i_compact     = abap_false
          i_plain       = iv_plain
          i_ignore_case = iv_ignore_case
          i_start_line  = lv_hunk_render_start
          i_code_review = abap_false
          it_blame         = it_blame
          it_blame_deleted = it_blame_deleted ).
        DATA(lv_hunk_rows) = extract_rows( lv_hunk_full_html ).
        IF lv_hunk_rows IS NOT INITIAL.
          APPEND lv_hunk_rows TO result.
        ENDIF.
      ENDIF.

      LOOP AT lt_hunk_diff INTO DATA(ls_hunk_render_count).
        IF ls_hunk_render_count-op = '=' OR ls_hunk_render_count-op = '+'.
          lv_hunk_render_line = lv_hunk_render_line + 1.
        ENDIF.
      ENDLOOP.
      lv_diff_pos = lv_hscan.
    ENDWHILE.
  ENDMETHOD.

  METHOD extract_rows.
    DATA lv_tb_off TYPE i.
    DATA lv_tb_len TYPE i.
    FIND FIRST OCCURRENCE OF `<table><tbody>` IN iv_html
      MATCH OFFSET lv_tb_off MATCH LENGTH lv_tb_len.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.

    DATA(lv_rows_start) = lv_tb_off + lv_tb_len.
    DATA(lv_rows_tail) = iv_html+lv_rows_start.
    DATA lv_rows_end TYPE i.
    FIND FIRST OCCURRENCE OF `</tbody></table>` IN lv_rows_tail MATCH OFFSET lv_rows_end.
    IF sy-subrc = 0.
      result = lv_rows_tail(lv_rows_end).
    ENDIF.
  ENDMETHOD.

  METHOD filter_moved_lines.
    result = it_diff.

    TYPES:
      BEGIN OF ty_del_candidate,
        key TYPE string,
        idx TYPE i,
      END OF ty_del_candidate.

    DATA lt_del_candidates TYPE HASHED TABLE OF ty_del_candidate WITH UNIQUE KEY key idx.
    DATA lt_drop_idx TYPE HASHED TABLE OF i WITH UNIQUE KEY table_line.
    DATA lt_used_del TYPE HASHED TABLE OF i WITH UNIQUE KEY table_line.

    LOOP AT result INTO DATA(ls_del_candidate) WHERE op = '-'.
      " Trivial structural lines (ENDIF./ELSE./ENDLOOP./…) match each other
      " everywhere — never treat them as "moved", or a demoted structural anchor
      " would be folded back into '=' and fragment the review into tiny hunks.
      IF zcl_code_popup_diff=>is_trivial_anchor( CONV string( ls_del_candidate-text ) ) = abap_true.
        CONTINUE.
      ENDIF.
      DATA(lv_del_candidate_key) = normalize_moved_line(
        iv_text        = CONV string( ls_del_candidate-text )
        iv_ignore_case = iv_ignore_case ).
      "CHECK strlen( lv_del_candidate_key ) >= 8.
      INSERT VALUE ty_del_candidate(
        key = lv_del_candidate_key
        idx = sy-tabix ) INTO TABLE lt_del_candidates.
    ENDLOOP.

    LOOP AT result INTO DATA(ls_ins) WHERE op = '+'.
      DATA(lv_ins_idx) = sy-tabix.

      DATA(lv_key) = normalize_moved_line(
        iv_text        = CONV string( ls_ins-text )
        iv_ignore_case = iv_ignore_case ).
      CHECK lv_key IS NOT INITIAL.
      "CHECK strlen( lv_key ) >= 8.

      LOOP AT lt_del_candidates INTO DATA(ls_del_candidate_match)
        WHERE key = lv_key.
        IF NOT line_exists( lt_used_del[ table_line = ls_del_candidate_match-idx ] ).
          result[ lv_ins_idx ]-op = '='.
          INSERT ls_del_candidate_match-idx INTO TABLE lt_drop_idx.
          INSERT ls_del_candidate_match-idx INTO TABLE lt_used_del.
          EXIT.
        ENDIF.
      ENDLOOP.
    ENDLOOP.

    DATA lt_filtered TYPE zif_code_popup_types=>ty_t_diff.
    LOOP AT result INTO DATA(ls_diff_row).
      IF line_exists( lt_drop_idx[ table_line = sy-tabix ] ).
        CONTINUE.
      ENDIF.
      APPEND ls_diff_row TO lt_filtered.
    ENDLOOP.
    result = lt_filtered.
  ENDMETHOD.

  METHOD normalize_moved_line.
    result = iv_text.
    CONDENSE result.
    DATA(lv_upper) = result.
    TRANSLATE lv_upper TO UPPER CASE.
    IF lv_upper CS `THIS CLASS HAS BEEN GENERATED`.
      result = `__AVE_GENERATED_CLASS_HEADER__`.
      RETURN.
    ENDIF.
    IF lv_upper CS `LC_GEN_DATE_TIME`
       AND lv_upper CS `TIMESTAMP`
       AND lv_upper CS `VALUE`.
      result = `__AVE_GENERATED_DATE_TIME__`.
      RETURN.
    ENDIF.
    IF iv_ignore_case = abap_true.
      TRANSLATE result TO UPPER CASE.
    ENDIF.
  ENDMETHOD.

  METHOD change_block_size.
    READ TABLE it_diff INTO DATA(ls_current) INDEX iv_index.
    IF sy-subrc <> 0 OR ( ls_current-op <> '+' AND ls_current-op <> '-' ).
      RETURN.
    ENDIF.

    result = 1.
    DATA(lv_scan) = iv_index - 1.
    WHILE lv_scan >= 1.
      READ TABLE it_diff INTO DATA(ls_before) INDEX lv_scan.
      IF sy-subrc <> 0 OR ( ls_before-op <> '+' AND ls_before-op <> '-' ).
        EXIT.
      ENDIF.
      result = result + 1.
      lv_scan = lv_scan - 1.
    ENDWHILE.

    lv_scan = iv_index + 1.
    WHILE lv_scan <= lines( it_diff ).
      READ TABLE it_diff INTO DATA(ls_after) INDEX lv_scan.
      IF sy-subrc <> 0 OR ( ls_after-op <> '+' AND ls_after-op <> '-' ).
        EXIT.
      ENDIF.
      result = result + 1.
      lv_scan = lv_scan + 1.
    ENDWHILE.
  ENDMETHOD.
ENDCLASS.
