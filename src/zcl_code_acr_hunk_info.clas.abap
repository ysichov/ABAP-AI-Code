CLASS zcl_code_acr_hunk_info DEFINITION
  PUBLIC
  FINAL
  CREATE PRIVATE.

  PUBLIC SECTION.
    CLASS-METHODS collect
      IMPORTING
        is_part            TYPE zif_code_popup_types=>ty_part_row
        it_diff            TYPE zif_code_popup_types=>ty_t_diff
        it_hunk_html       TYPE string_table
        it_blame           TYPE zif_code_popup_types=>ty_blame_map
        iv_author          TYPE versuser
        iv_display_name    TYPE string
        iv_versno_new      TYPE versno
        iv_versno_old      TYPE versno
        iv_versno_new_text TYPE string
        iv_versno_old_text TYPE string
        iv_is_created      TYPE abap_bool
      EXPORTING
        et_hunk_info       TYPE zif_code_acr_types=>ty_t_hunk_info
        ev_hunk_count      TYPE i
        ev_hunk_ins        TYPE i
        ev_hunk_mod        TYPE i
        ev_hunk_del        TYPE i.

  PRIVATE SECTION.
    CLASS-METHODS has_visible_change
      IMPORTING
        iv_html        TYPE string
      RETURNING
        VALUE(result)  TYPE abap_bool.
ENDCLASS.


CLASS zcl_code_acr_hunk_info IMPLEMENTATION.

  METHOD collect.
    CLEAR: et_hunk_info, ev_hunk_count, ev_hunk_ins, ev_hunk_mod, ev_hunk_del.

    DATA lv_hunk_html_idx TYPE i VALUE 0.
    DATA lv_in_hunk TYPE abap_bool VALUE abap_false.
    DATA lt_cur_hunk TYPE string_table.
    DATA lv_new_line TYPE i VALUE 0.
    DATA lv_hunk_line TYPE i.
    DATA lv_hunk_chg TYPE i.
    DATA lv_hunk_ins TYPE i.
    DATA lv_hunk_del TYPE i.
    DATA lv_hunk_auth TYPE versuser.

    DATA lt_ops TYPE zif_code_popup_types=>ty_t_diff.
    lt_ops = it_diff.
    APPEND VALUE #( op = '=' ) TO lt_ops.

    LOOP AT lt_ops INTO DATA(ls_dop).
      CASE ls_dop-op.
        WHEN '+' OR '-'.
          IF lv_in_hunk = abap_false.
            lv_in_hunk = abap_true.
            CLEAR: lt_cur_hunk, lv_hunk_chg, lv_hunk_ins, lv_hunk_del, lv_hunk_auth.
            lv_hunk_line = lv_new_line + 1.
          ENDIF.
          lv_hunk_chg = lv_hunk_chg + 1.
          IF ls_dop-op = '+'.
            lv_hunk_ins = lv_hunk_ins + 1.
            IF lv_hunk_auth IS INITIAL AND it_blame IS NOT INITIAL.
              READ TABLE it_blame INTO DATA(ls_hb) WITH KEY text = ls_dop-text.
              IF sy-subrc = 0.
                lv_hunk_auth = ls_hb-author.
              ENDIF.
            ENDIF.
            lv_new_line = lv_new_line + 1.
          ELSE.
            lv_hunk_del = lv_hunk_del + 1.
          ENDIF.
          APPEND CONV string( ls_dop-text ) TO lt_cur_hunk.
        WHEN OTHERS.
          IF lv_in_hunk = abap_true.
            IF ls_dop-op = '=' AND condense( val = ls_dop-text ) = ``.
              DATA(lv_dpeek_idx) = sy-tabix + 1.
              DATA(lv_dextra) = 0.
              DATA(lv_dmore_changes) = abap_false.
              WHILE lv_dpeek_idx <= lines( lt_ops ).
                READ TABLE lt_ops INTO DATA(ls_dpeek) INDEX lv_dpeek_idx.
                IF ls_dpeek-op = '-' OR ls_dpeek-op = '+'.
                  lv_dmore_changes = abap_true.
                  EXIT.
                ELSEIF ls_dpeek-op = '=' AND condense( val = ls_dpeek-text ) = `` AND lv_dextra < 1.
                  lv_dextra = lv_dextra + 1.
                  lv_dpeek_idx = lv_dpeek_idx + 1.
                  CONTINUE.
                ELSE.
                  EXIT.
                ENDIF.
              ENDWHILE.
              IF lv_dmore_changes = abap_true.
                APPEND CONV string( ls_dop-text ) TO lt_cur_hunk.
                lv_new_line = lv_new_line + 1.
                CONTINUE.
              ENDIF.
            ENDIF.

            IF zcl_code_acr_stats=>is_blank_hunk( lt_cur_hunk ) = abap_false.
              lv_hunk_html_idx = lv_hunk_html_idx + 1.
              DATA(lv_hunk_kind) = COND string(
                WHEN lv_hunk_ins > 0 AND lv_hunk_del > 0 THEN `changed`
                WHEN lv_hunk_ins > 0                      THEN `added`
                WHEN lv_hunk_del > 0                      THEN `deleted`
                ELSE                                           `changed` ).
              DATA(lv_info_author) = COND versuser(
                WHEN iv_is_created = abap_true THEN iv_author
                WHEN lv_hunk_auth IS NOT INITIAL THEN lv_hunk_auth
                ELSE iv_author ).
              DATA lv_info_html TYPE string.
              READ TABLE it_hunk_html INTO lv_info_html INDEX lv_hunk_html_idx.
              IF has_visible_change( lv_info_html ) = abap_true.
                ev_hunk_count = ev_hunk_count + 1.
                CASE lv_hunk_kind.
                  WHEN `added`.   ev_hunk_ins = ev_hunk_ins + 1.
                  WHEN `changed`. ev_hunk_mod = ev_hunk_mod + 1.
                  WHEN `deleted`. ev_hunk_del = ev_hunk_del + 1.
                ENDCASE.
                INSERT VALUE zif_code_acr_types=>ty_hunk_info(
                  hunk_key        = |{ is_part-type }~{ is_part-object_name }~{ ev_hunk_count }|
                  objtype         = is_part-type
                  obj_name        = is_part-object_name
                  class_name      = CONV #( is_part-class )
                  display_name    = iv_display_name
                  hunk_no         = ev_hunk_count
                  start_line      = lv_hunk_line
                  change_count    = lv_hunk_chg
                  change_kind     = lv_hunk_kind
                  author          = lv_info_author
                  author_name     = zcl_code_popup_data=>get_user_name( lv_info_author )
                  versno_new      = iv_versno_new
                  versno_old      = iv_versno_old
                  versno_new_text = iv_versno_new_text
                  versno_old_text = iv_versno_old_text
                  html            = lv_info_html )
                  INTO TABLE et_hunk_info.
              ENDIF.
            ENDIF.
            lv_in_hunk = abap_false.
            CLEAR: lt_cur_hunk, lv_hunk_chg, lv_hunk_ins, lv_hunk_del, lv_hunk_auth.
          ENDIF.
          lv_new_line = lv_new_line + 1.
      ENDCASE.
    ENDLOOP.
  ENDMETHOD.

  METHOD has_visible_change.
    result = boolc( iv_html CS `#ffb3b3`
                 OR iv_html CS `#afffaf`
                 OR iv_html CS `background:#ffecec`
                 OR iv_html CS `background:#eaffea` ).
  ENDMETHOD.
ENDCLASS.
