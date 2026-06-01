class ZCL_CODE_ANSWER_TOOLS definition
  public
  create public .

public section.

  class-methods EXTRACT_CODE_FROM_ANSWER
    importing
      !I_TEXT type STRING
    returning
      value(RV_CODE) type STRING .
protected section.
private section.
ENDCLASS.



CLASS ZCL_CODE_ANSWER_TOOLS IMPLEMENTATION.


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
ENDCLASS.
