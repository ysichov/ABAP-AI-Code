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
  class-methods MERGE_CLASS_PARTS
    importing
      !I_FULL_SOURCE    type STRING
      !I_CHANGED_SOURCE type STRING
    returning
      value(RV_MERGED)  type STRING .
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
  class-methods APPEND_CHANGED_WINDOW
    importing
      !IT_CURRENT type STRING_TABLE
      !IT_PROPOSED type STRING_TABLE
      !I_CURRENT_FROM type I
      !I_CURRENT_TO type I
      !I_PROPOSED_FROM type I
      !I_PROPOSED_TO type I
    changing
      !CV_CURRENT_SOURCE type STRING
      !CV_PROPOSED_SOURCE type STRING .
ENDCLASS.



CLASS ZCL_CODE_ANSWER_TOOLS IMPLEMENTATION.


  method APPEND_CHANGED_WINDOW.

    DATA lv_current_from TYPE i.
    DATA lv_current_to TYPE i.
    DATA lv_proposed_from TYPE i.
    DATA lv_proposed_to TYPE i.
    DATA lv_current_context_from TYPE i.
    DATA lv_current_context_to TYPE i.
    DATA lv_proposed_context_from TYPE i.
    DATA lv_proposed_context_to TYPE i.
    DATA lv_current_slice TYPE string.
    DATA lv_proposed_slice TYPE string.
    DATA lv_current_norm TYPE string.
    DATA lv_proposed_norm TYPE string.

    lv_current_from = i_current_from.
    lv_current_to = i_current_to.
    lv_proposed_from = i_proposed_from.
    lv_proposed_to = i_proposed_to.

    IF lv_current_to < lv_current_from.
      lv_current_context_from = lv_current_from.
      lv_current_context_to = lv_current_from - 1.
    ELSE.
      lv_current_context_from = lv_current_from.
      lv_current_context_to = lv_current_to.
    ENDIF.

    IF lv_proposed_to < lv_proposed_from.
      lv_proposed_context_from = lv_proposed_from.
      lv_proposed_context_to = lv_proposed_from - 1.
    ELSE.
      lv_proposed_context_from = lv_proposed_from.
      lv_proposed_context_to = lv_proposed_to.
    ENDIF.

    lv_current_slice = slice_source(
      it_lines = it_current
      i_from   = lv_current_context_from
      i_to     = lv_current_context_to ).
    lv_proposed_slice = slice_source(
      it_lines = it_proposed
      i_from   = lv_proposed_context_from
      i_to     = lv_proposed_context_to ).

    lv_current_norm = lv_current_slice.
    lv_proposed_norm = lv_proposed_slice.
    CONDENSE lv_current_norm.
    CONDENSE lv_proposed_norm.

    IF lv_current_norm = lv_proposed_norm.
      RETURN.
    ENDIF.

    IF cv_current_source IS NOT INITIAL
    AND lv_current_slice IS NOT INITIAL.
      cv_current_source = cv_current_source && cl_abap_char_utilities=>newline.
    ENDIF.
    cv_current_source = cv_current_source && lv_current_slice.

    IF cv_proposed_source IS NOT INITIAL
    AND lv_proposed_slice IS NOT INITIAL.
      cv_proposed_source = cv_proposed_source && cl_abap_char_utilities=>newline.
    ENDIF.
    cv_proposed_source = cv_proposed_source && lv_proposed_slice.

  endmethod.


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

    DATA(lv_text) = i_text.
    REPLACE ALL OCCURRENCES OF REGEX '(^|[\r\n]+)\s*CHANGES\s*:\s*(YES|NO)\s*' IN lv_text WITH ''.

    FIND FIRST OCCURRENCE OF REGEX '```\s*[Aa][Bb][Aa][Pp]\s*' IN lv_text
      MATCH OFFSET lv_start
      MATCH LENGTH lv_fence_len.
    IF sy-subrc = 0.
      lv_code_start = lv_start + lv_fence_len.
      lv_after = substring( val = lv_text off = lv_code_start ).
      FIND FIRST OCCURRENCE OF '```' IN lv_after MATCH OFFSET lv_end.
      IF sy-subrc <> 0.
        rv_code = lv_after.
      ELSE.
        rv_code = substring( val = lv_after len = lv_end ).
      ENDIF.
      SHIFT rv_code LEFT DELETING LEADING cl_abap_char_utilities=>newline.
      RETURN.
    ENDIF.

    FIND FIRST OCCURRENCE OF REGEX '```\s*[A-Za-z0-9_-]*\s*' IN lv_text
      MATCH OFFSET lv_start
      MATCH LENGTH lv_fence_len.
    IF sy-subrc <> 0.
      rv_code = lv_text.
      RETURN.
    ENDIF.

    lv_code_start = lv_start + lv_fence_len.
    lv_after = substring( val = lv_text off = lv_code_start ).
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
    DATA lv_current_idx TYPE i.
    DATA lv_proposed_idx TYPE i.
    DATA lv_current_anchor TYPE i.
    DATA lv_proposed_anchor TYPE i.
    DATA lv_found TYPE abap_bool.
    DATA lv_search_to TYPE i.
    DATA lv_current_search TYPE i.
    DATA lv_proposed_search TYPE i.

    e_current_source = i_current_source.
    e_proposed_source = i_proposed_source.

    IF i_current_source = i_proposed_source.
      RETURN.
    ENDIF.

    SPLIT i_current_source AT cl_abap_char_utilities=>newline INTO TABLE lt_current.
    SPLIT i_proposed_source AT cl_abap_char_utilities=>newline INTO TABLE lt_proposed.

    CLEAR: e_current_source,
           e_proposed_source.

    lv_current_idx = 1.
    lv_proposed_idx = 1.

    WHILE lv_current_idx <= lines( lt_current )
       OR lv_proposed_idx <= lines( lt_proposed ).

      IF lv_current_idx <= lines( lt_current )
      AND lv_proposed_idx <= lines( lt_proposed )
      AND lt_current[ lv_current_idx ] = lt_proposed[ lv_proposed_idx ].
        lv_current_idx = lv_current_idx + 1.
        lv_proposed_idx = lv_proposed_idx + 1.
        CONTINUE.
      ENDIF.

      CLEAR: lv_found,
             lv_current_anchor,
             lv_proposed_anchor.

      IF lv_current_idx <= lines( lt_current ).
        lv_search_to = nmin( val1 = lv_proposed_idx + 30 val2 = lines( lt_proposed ) ).
        lv_proposed_search = lv_proposed_idx + 1.
        WHILE lv_proposed_search <= lv_search_to.
          IF lt_proposed[ lv_proposed_search ] = lt_current[ lv_current_idx ].
            lv_current_anchor = lv_current_idx.
            lv_proposed_anchor = lv_proposed_search.
            lv_found = abap_true.
            EXIT.
          ENDIF.
          lv_proposed_search = lv_proposed_search + 1.
        ENDWHILE.
      ENDIF.

      IF lv_found = abap_false
      AND lv_proposed_idx <= lines( lt_proposed ).
        lv_search_to = nmin( val1 = lv_current_idx + 30 val2 = lines( lt_current ) ).
        lv_current_search = lv_current_idx + 1.
        WHILE lv_current_search <= lv_search_to.
          IF lt_current[ lv_current_search ] = lt_proposed[ lv_proposed_idx ].
            lv_current_anchor = lv_current_search.
            lv_proposed_anchor = lv_proposed_idx.
            lv_found = abap_true.
            EXIT.
          ENDIF.
          lv_current_search = lv_current_search + 1.
        ENDWHILE.
      ENDIF.

      IF lv_found = abap_false.
        lv_current_anchor = lines( lt_current ) + 1.
        lv_proposed_anchor = lines( lt_proposed ) + 1.
      ENDIF.

      append_changed_window(
        EXPORTING
          it_current       = lt_current
          it_proposed      = lt_proposed
          i_current_from   = lv_current_idx
          i_current_to     = lv_current_anchor - 1
          i_proposed_from  = lv_proposed_idx
          i_proposed_to    = lv_proposed_anchor - 1
        CHANGING
          cv_current_source  = e_current_source
          cv_proposed_source = e_proposed_source ).

      lv_current_idx = lv_current_anchor.
      lv_proposed_idx = lv_proposed_anchor.
    ENDWHILE.

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
      " Skip lone markdown hr lines (--- or ---- without title)
      DATA(lv_line_hr) = lv_line.
      CONDENSE lv_line_hr.
      FIND FIRST OCCURRENCE OF REGEX '^-+$' IN lv_line_hr.
      IF sy-subrc = 0.
        CONTINUE.
      ENDIF.

      " XML closing tag </section> or </Method X> — end of current part, skip line
      " Allow trailing garbage (e.g. </public section>Total tokens: ...)
      FIND FIRST OCCURRENCE OF REGEX '^</[^>]+>' IN lv_line IGNORING CASE.
      IF sy-subrc = 0.
        CONTINUE.
      ENDIF.

      " XML opening tag <public section>, <Method NAME>, etc.
      FIND FIRST OCCURRENCE OF REGEX '^<([^/][^>]*)>\s*$' IN lv_line
        IGNORING CASE SUBMATCHES lv_title.
      IF sy-subrc = 0.
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

      " Legacy --- title --- format (check BEFORE stripping trailing dashes)
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

      " Strip trailing --- that LLM appends (markdown hr artifact)
      " Must be AFTER --- title --- check to avoid breaking section headers
      REPLACE FIRST OCCURRENCE OF REGEX '-{2,}\s*$' IN lv_line WITH '' IGNORING CASE.

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
      DATA(lv_line) = it_lines[ lv_index ].
      DATA(lv_line_check) = lv_line.
      CONDENSE lv_line_check.
      IF lv_line_check IS INITIAL.
        lv_index = lv_index + 1.
        CONTINUE.
      ENDIF.

      IF rv_source IS NOT INITIAL.
        rv_source = rv_source && cl_abap_char_utilities=>newline.
      ENDIF.
      rv_source = rv_source && lv_line.
      lv_index = lv_index + 1.
    ENDWHILE.

  endmethod.


  METHOD merge_class_parts.
    " Strip CHANGES:YES/NO marker and lone --- (markdown hr) lines
    DATA(lv_changed) = i_changed_source.
    REPLACE ALL OCCURRENCES OF REGEX '[\r\n]+\s*CHANGES\s*:\s*(YES|NO)\s*$'
      IN lv_changed WITH '' IGNORING CASE.
    REPLACE ALL OCCURRENCES OF REGEX '(^|\n)\s*---\s*(\n|$)'
      IN lv_changed WITH cl_abap_char_utilities=>newline IGNORING CASE.

    " Parse full old class into parts map
    DATA(lt_old_parts) = extract_class_parts( i_full_source ).
    DATA(lt_new_parts) = extract_class_parts( lv_changed ).

    IF lt_new_parts IS INITIAL.
      " Changed source has no --- section --- markers: return unchanged
      rv_merged = i_full_source.
      RETURN.
    ENDIF.

    IF lt_old_parts IS INITIAL.
      " No old parts: return changed source as-is
      rv_merged = lv_changed.
      RETURN.
    ENDIF.

    " Override old parts with new (changed) parts
    LOOP AT lt_new_parts INTO DATA(ls_new).
      READ TABLE lt_old_parts ASSIGNING FIELD-SYMBOL(<ls_old>)
        WITH KEY part_key = ls_new-part_key.
      IF sy-subrc = 0.
        " If old method source had METHOD X. / ENDMETHOD. wrappers and new source doesn't — add them
        DATA(lv_new_first) = ls_new-source.
        FIND FIRST OCCURRENCE OF cl_abap_char_utilities=>newline IN lv_new_first.
        IF sy-subrc = 0.
          lv_new_first = lv_new_first(sy-fdpos).
        ENDIF.
        DATA(lv_new_first_upper) = lv_new_first.
        CONDENSE lv_new_first_upper.
        TRANSLATE lv_new_first_upper TO UPPER CASE.

        DATA(lv_old_first) = <ls_old>-source.
        FIND FIRST OCCURRENCE OF cl_abap_char_utilities=>newline IN lv_old_first.
        IF sy-subrc = 0.
          lv_old_first = lv_old_first(sy-fdpos).
        ENDIF.
        DATA(lv_old_first_upper) = lv_old_first.
        CONDENSE lv_old_first_upper.
        TRANSLATE lv_old_first_upper TO UPPER CASE.

        IF lv_old_first_upper CP 'METHOD *' AND NOT lv_new_first_upper CP 'METHOD *'.
          " New source is body only — wrap with METHOD/ENDMETHOD from old
          DATA(lv_meth_name) = ls_new-part_key.
          REPLACE FIRST OCCURRENCE OF 'METHOD:' IN lv_meth_name WITH ''.
          ls_new-source = |METHOD { lv_meth_name }.|
                       && cl_abap_char_utilities=>newline
                       && ls_new-source
                       && cl_abap_char_utilities=>newline
                       && |ENDMETHOD.|.
        ENDIF.

        IF ls_new-part_key CP 'METHOD:*'.
          " Method: extract body between METHOD./ENDMETHOD., skip if empty
          DATA(lv_meth_body) = ls_new-source.
          REPLACE FIRST OCCURRENCE OF REGEX '^\s*METHOD\s+\S[^\n]*\n?'
            IN lv_meth_body WITH '' IGNORING CASE.
          REPLACE FIRST OCCURRENCE OF REGEX '\n?\s*ENDMETHOD\s*\.?\s*$'
            IN lv_meth_body WITH '' IGNORING CASE.
          DATA(lv_meth_body_check) = lv_meth_body.
          CONDENSE lv_meth_body_check.
          IF lv_meth_body_check IS INITIAL.
            " Empty method body returned by LLM — skip, keep existing
            CONTINUE.
          ENDIF.
          <ls_old>-source = ls_new-source.
          <ls_old>-title  = ls_new-title.
        ELSE.
          " Section (public/protected/private): append delta to existing content
          IF <ls_old>-source IS NOT INITIAL AND ls_new-source IS NOT INITIAL.
            <ls_old>-source = <ls_old>-source
                           && cl_abap_char_utilities=>newline
                           && ls_new-source.
          ELSEIF ls_new-source IS NOT INITIAL.
            <ls_old>-source = ls_new-source.
          ENDIF.
        ENDIF.
      ELSE.
        " New method not in old class — no wrapping needed (LLM provides full method)
        APPEND ls_new TO lt_old_parts.
      ENDIF.
    ENDLOOP.

    " Reconstruct full source from merged parts
    LOOP AT lt_old_parts INTO DATA(ls_part).
      IF rv_merged IS NOT INITIAL.
        rv_merged = rv_merged
                 && cl_abap_char_utilities=>newline
                 && cl_abap_char_utilities=>newline.
      ENDIF.
      rv_merged = rv_merged
               && |--- { ls_part-title } ---|
               && cl_abap_char_utilities=>newline
               && ls_part-source.
    ENDLOOP.

  ENDMETHOD.
ENDCLASS.
