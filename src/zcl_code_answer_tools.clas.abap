class ZCL_CODE_ANSWER_TOOLS definition
  public
  create public .

public section.

  types:
    BEGIN OF TY_CLASS_PART,
      PART_KEY type STRING,
      TITLE type STRING,
      SOURCE type STRING,
    END OF TY_CLASS_PART .
  types TT_CLASS_PARTS type STANDARD TABLE OF TY_CLASS_PART WITH NON-UNIQUE DEFAULT KEY .

  class-methods EXTRACT_CODE_FROM_ANSWER
    importing
      !I_TEXT type STRING
    returning
      value(RV_CODE) type STRING .
  class-methods EXTRACT_CLASS_PARTS
    importing
      !I_SOURCE type STRING
    returning
      value(RT_PARTS) type TT_CLASS_PARTS .
  class-methods EXTRACT_CHANGED_CONTEXT
    importing
      !I_CURRENT_SOURCE type STRING
      !I_PROPOSED_SOURCE type STRING
    exporting
      !E_CURRENT_SOURCE type STRING
      !E_PROPOSED_SOURCE type STRING .
protected section.
private section.
  class-methods APPEND_CLASS_PART
    importing
      !IS_PART type TY_CLASS_PART
    changing
      !CT_PARTS type TT_CLASS_PARTS .
  class-methods NORMALIZE_CLASS_PART_KEY
    importing
      !I_TITLE type STRING
    returning
      value(RV_KEY) type STRING .
  class-methods SLICE_SOURCE
    importing
      !IT_LINES type STRING_TABLE
      !I_FROM type I
      !I_TO type I
    returning
      value(RV_SOURCE) type STRING .
ENDCLASS.



CLASS ZCL_CODE_ANSWER_TOOLS IMPLEMENTATION.


  method APPEND_CLASS_PART.

    IF is_part-part_key IS INITIAL.
      RETURN.
    ENDIF.

    READ TABLE ct_parts ASSIGNING FIELD-SYMBOL(<ls_part>)
      WITH KEY part_key = is_part-part_key.
    IF sy-subrc = 0.
      IF <ls_part>-source IS NOT INITIAL
      AND is_part-source IS NOT INITIAL.
        <ls_part>-source = <ls_part>-source
                         && cl_abap_char_utilities=>newline
                         && is_part-source.
      ELSEIF is_part-source IS NOT INITIAL.
        <ls_part>-source = is_part-source.
      ENDIF.
      RETURN.
    ENDIF.

    APPEND is_part TO ct_parts.

  endmethod.


  method EXTRACT_CODE_FROM_ANSWER.

    DATA lv_start TYPE i.
    DATA lv_fence_len TYPE i.
    DATA lv_code_start TYPE i.
    DATA lv_end TYPE i.
    DATA lv_after TYPE string.

    FIND FIRST OCCURRENCE OF REGEX '```\s*[Aa][Bb][Aa][Pp]\s*' IN i_text
      MATCH OFFSET lv_start
      MATCH LENGTH lv_fence_len.
    IF sy-subrc = 0.
      lv_code_start = lv_start + lv_fence_len.
      lv_after = substring( val = i_text off = lv_code_start ).
      FIND FIRST OCCURRENCE OF '```' IN lv_after MATCH OFFSET lv_end.
      IF sy-subrc <> 0.
        rv_code = lv_after.
      ELSE.
        rv_code = substring( val = lv_after len = lv_end ).
      ENDIF.
      SHIFT rv_code LEFT DELETING LEADING cl_abap_char_utilities=>newline.
      RETURN.
    ENDIF.

    FIND FIRST OCCURRENCE OF REGEX '```\s*[A-Za-z0-9_-]*\s*' IN i_text
      MATCH OFFSET lv_start
      MATCH LENGTH lv_fence_len.
    IF sy-subrc <> 0.
      rv_code = i_text.
      RETURN.
    ENDIF.

    lv_code_start = lv_start + lv_fence_len.
    lv_after = substring( val = i_text off = lv_code_start ).
    FIND FIRST OCCURRENCE OF '```' IN lv_after MATCH OFFSET lv_end.
    IF sy-subrc <> 0.
      rv_code = lv_after.
      RETURN.
    ENDIF.

    rv_code = substring( val = lv_after len = lv_end ).
    SHIFT rv_code LEFT DELETING LEADING cl_abap_char_utilities=>newline.

  endmethod.


  method EXTRACT_CHANGED_CONTEXT.

    DATA lt_current TYPE string_table.
    DATA lt_proposed TYPE string_table.
    DATA lv_first TYPE i.
    DATA lv_current_last TYPE i.
    DATA lv_proposed_last TYPE i.
    DATA lv_current_start TYPE i.
    DATA lv_proposed_start TYPE i.
    DATA lv_current_end TYPE i.
    DATA lv_proposed_end TYPE i.
    DATA lv_min_lines TYPE i.

    e_current_source = i_current_source.
    e_proposed_source = i_proposed_source.

    IF i_current_source = i_proposed_source.
      RETURN.
    ENDIF.

    SPLIT i_current_source AT cl_abap_char_utilities=>newline INTO TABLE lt_current.
    SPLIT i_proposed_source AT cl_abap_char_utilities=>newline INTO TABLE lt_proposed.

    lv_min_lines = nmin( val1 = lines( lt_current ) val2 = lines( lt_proposed ) ).
    lv_first = 1.
    WHILE lv_first <= lv_min_lines.
      IF lt_current[ lv_first ] <> lt_proposed[ lv_first ].
        EXIT.
      ENDIF.
      lv_first = lv_first + 1.
    ENDWHILE.

    lv_current_last = lines( lt_current ).
    lv_proposed_last = lines( lt_proposed ).
    WHILE lv_current_last >= lv_first
      AND lv_proposed_last >= lv_first.
      IF lt_current[ lv_current_last ] <> lt_proposed[ lv_proposed_last ].
        EXIT.
      ENDIF.
      lv_current_last = lv_current_last - 1.
      lv_proposed_last = lv_proposed_last - 1.
    ENDWHILE.

    lv_current_start = lv_first - 3.
    lv_proposed_start = lv_first - 3.
    IF lv_current_start < 1.
      lv_current_start = 1.
    ENDIF.
    IF lv_proposed_start < 1.
      lv_proposed_start = 1.
    ENDIF.

    lv_current_end = lv_current_last + 3.
    lv_proposed_end = lv_proposed_last + 3.
    IF lv_current_end > lines( lt_current ).
      lv_current_end = lines( lt_current ).
    ENDIF.
    IF lv_proposed_end > lines( lt_proposed ).
      lv_proposed_end = lines( lt_proposed ).
    ENDIF.

    e_current_source = slice_source(
      it_lines = lt_current
      i_from   = lv_current_start
      i_to     = lv_current_end ).
    e_proposed_source = slice_source(
      it_lines = lt_proposed
      i_from   = lv_proposed_start
      i_to     = lv_proposed_end ).

  endmethod.


  method EXTRACT_CLASS_PARTS.

    DATA lt_lines TYPE STANDARD TABLE OF string WITH NON-UNIQUE DEFAULT KEY.
    DATA ls_part TYPE ty_class_part.
    DATA lv_title TYPE string.
    DATA lv_line TYPE string.
    DATA lv_header_prefix TYPE string.
    DATA lv_section TYPE string.
    DATA lv_method TYPE string.
    DATA lv_preamble TYPE string.

    SPLIT i_source AT cl_abap_char_utilities=>newline INTO TABLE lt_lines.

    LOOP AT lt_lines INTO lv_line.
      FIND FIRST OCCURRENCE OF REGEX '^---\s+(.+)---\s*$'
        IN lv_line SUBMATCHES lv_title.
      IF sy-subrc = 0.
        REPLACE FIRST OCCURRENCE OF REGEX '\s+\([^)]+\)\s*$' IN lv_title WITH ''.
        CONDENSE lv_title.

        append_class_part(
          EXPORTING
            is_part = ls_part
          CHANGING
            ct_parts = rt_parts ).

        CLEAR ls_part.
        ls_part-title = lv_title.
        ls_part-part_key = normalize_class_part_key( lv_title ).
        IF lv_preamble IS NOT INITIAL.
          ls_part-source = lv_preamble.
          CLEAR lv_preamble.
        ENDIF.
        CONTINUE.
      ENDIF.

      FIND FIRST OCCURRENCE OF REGEX '^\s*(PUBLIC|PROTECTED|PRIVATE)\s+SECTION\s*\.'
        IN lv_line IGNORING CASE SUBMATCHES lv_section.
      IF sy-subrc = 0.
        append_class_part(
          EXPORTING
            is_part = ls_part
          CHANGING
            ct_parts = rt_parts ).

        TRANSLATE lv_section TO LOWER CASE.
        CONCATENATE lv_section 'section' INTO lv_title SEPARATED BY space.
        CLEAR ls_part.
        ls_part-title = lv_title.
        ls_part-part_key = normalize_class_part_key( lv_title ).
        IF lv_preamble IS NOT INITIAL.
          ls_part-source = lv_preamble.
          CLEAR lv_preamble.
        ENDIF.
      ELSE.
        FIND FIRST OCCURRENCE OF REGEX '^\s*METHOD\s+([A-Za-z0-9_~/]+)\s*\.'
          IN lv_line IGNORING CASE SUBMATCHES lv_method.
        IF sy-subrc = 0.
          append_class_part(
            EXPORTING
              is_part = ls_part
            CHANGING
              ct_parts = rt_parts ).

          TRANSLATE lv_method TO UPPER CASE.
          CONCATENATE 'Method' lv_method INTO lv_title SEPARATED BY space.
          CLEAR ls_part.
          ls_part-title = lv_title.
          ls_part-part_key = normalize_class_part_key( lv_title ).
          IF lv_preamble IS NOT INITIAL.
            ls_part-source = lv_preamble.
            CLEAR lv_preamble.
          ENDIF.
        ENDIF.
      ENDIF.

      IF ls_part-part_key IS INITIAL.
        lv_header_prefix = lv_line.
        CONDENSE lv_header_prefix.
        IF lv_header_prefix IS INITIAL
        OR lv_header_prefix CP 'Source for class *:'.
          CONTINUE.
        ENDIF.

        IF lv_preamble IS NOT INITIAL.
          lv_preamble = lv_preamble && cl_abap_char_utilities=>newline.
        ENDIF.
        lv_preamble = lv_preamble && lv_line.
        CONTINUE.
      ENDIF.

      IF ls_part-source IS NOT INITIAL.
        ls_part-source = ls_part-source && cl_abap_char_utilities=>newline.
      ENDIF.
      ls_part-source = ls_part-source && lv_line.
    ENDLOOP.

    append_class_part(
      EXPORTING
        is_part = ls_part
      CHANGING
        ct_parts = rt_parts ).

  endmethod.


  method NORMALIZE_CLASS_PART_KEY.

    DATA lv_name TYPE string.

    rv_key = i_title.
    CONDENSE rv_key.
    TRANSLATE rv_key TO UPPER CASE.

    FIND FIRST OCCURRENCE OF REGEX '^METHOD\s+(.+)$' IN rv_key SUBMATCHES lv_name.
    IF sy-subrc = 0.
      rv_key = |METHOD:{ lv_name }|.
      RETURN.
    ENDIF.

    FIND FIRST OCCURRENCE OF REGEX '^PUBLIC\s+SECTION' IN rv_key.
    IF sy-subrc = 0.
      rv_key = 'SECTION:PUBLIC'.
      RETURN.
    ENDIF.

    FIND FIRST OCCURRENCE OF REGEX '^PRIVATE\s+SECTION' IN rv_key.
    IF sy-subrc = 0.
      rv_key = 'SECTION:PRIVATE'.
      RETURN.
    ENDIF.

    FIND FIRST OCCURRENCE OF REGEX '^PROTECTED\s+SECTION' IN rv_key.
    IF sy-subrc = 0.
      rv_key = 'SECTION:PROTECTED'.
      RETURN.
    ENDIF.

    rv_key = |PART:{ rv_key }|.

  endmethod.


  method SLICE_SOURCE.

    DATA lv_index TYPE i.
    DATA lv_to TYPE i.

    IF it_lines IS INITIAL
    OR i_to < i_from.
      RETURN.
    ENDIF.

    lv_index = i_from.
    lv_to = i_to.
    IF lv_index < 1.
      lv_index = 1.
    ENDIF.
    IF lv_to > lines( it_lines ).
      lv_to = lines( it_lines ).
    ENDIF.

    WHILE lv_index <= lv_to.
      IF rv_source IS NOT INITIAL.
        rv_source = rv_source && cl_abap_char_utilities=>newline.
      ENDIF.
      rv_source = rv_source && it_lines[ lv_index ].
      lv_index = lv_index + 1.
    ENDWHILE.

  endmethod.
ENDCLASS.
