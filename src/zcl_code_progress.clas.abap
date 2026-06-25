"! Cooperative long-running loop interrupter.
"! After `threshold_secs` of continuous work, asks the user whether to
"! continue or stop. Caller decides how to react to a Stop (e.g. break
"! out of the loop with `was_stopped( )`).
CLASS zcl_code_progress DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    METHODS constructor
      IMPORTING i_title          TYPE csequence DEFAULT 'Long-running operation'
                i_threshold_secs TYPE i         DEFAULT 10
                i_confirm_key    TYPE csequence OPTIONAL.

    "! Call once per iteration. Returns abap_true → caller should stop.
    "! i_remaining is used both for the SAPGUI progress bar percentage
    "! (together with i_total) and for the confirmation text.
    METHODS check
      IMPORTING i_remaining   TYPE i OPTIONAL
                i_total       TYPE i OPTIONAL
                i_text        TYPE csequence OPTIONAL
      RETURNING VALUE(result) TYPE abap_bool.

    METHODS was_stopped
      RETURNING VALUE(result) TYPE abap_bool.

    CLASS-METHODS reset_stop.

    CLASS-METHODS was_stop_requested
      RETURNING VALUE(result) TYPE abap_bool.

  PRIVATE SECTION.
    DATA mv_title     TYPE string.
    DATA mv_confirm_key TYPE string.
    DATA mv_threshold TYPE i.
    DATA mv_ts_start    TYPE timestampl.
    DATA mv_ts_last_bar TYPE timestampl.
    DATA mv_stopped     TYPE abap_bool.
    CLASS-DATA mv_stop_requested TYPE abap_bool.
    CLASS-DATA mt_confirmed_keys TYPE HASHED TABLE OF string WITH UNIQUE KEY table_line.
ENDCLASS.


CLASS zcl_code_progress IMPLEMENTATION.

  METHOD constructor.
    mv_title     = i_title.
    mv_confirm_key = COND string(
      WHEN i_confirm_key IS NOT INITIAL THEN i_confirm_key
      ELSE CONV string( i_title ) ).
    mv_threshold = i_threshold_secs.
    GET TIME STAMP FIELD mv_ts_start.
    mv_ts_last_bar = mv_ts_start.
  ENDMETHOD.

  METHOD check.
    IF mv_stopped = abap_true.
      result = abap_true.
      RETURN.
    ENDIF.

    DATA lv_now  TYPE timestampl.
    DATA lv_secs TYPE tzntstmpl.
    GET TIME STAMP FIELD lv_now.

    " SAPGUI progress bar — throttle to once per second so cheap iterations
    " don't flood the GUI with roundtrips.
    cl_abap_tstmp=>subtract(
      EXPORTING tstmp1 = lv_now tstmp2 = mv_ts_last_bar
      RECEIVING r_secs = lv_secs ).
    IF lv_secs >= 1 AND i_total > 0 AND i_remaining >= 0.
      DATA(lv_done) = i_total - i_remaining.
      DATA(lv_pct)  = CONV i( lv_done * 100 / i_total ).

      " ETA: elapsed * remaining / done
      DATA lv_elapsed TYPE tzntstmpl.
      cl_abap_tstmp=>subtract(
        EXPORTING tstmp1 = lv_now tstmp2 = mv_ts_start
        RECEIVING r_secs = lv_elapsed ).
      DATA(lv_eta) = ``.
      IF lv_done > 0 AND lv_elapsed > 0.
        DATA(lv_eta_secs) = CONV i( lv_elapsed * i_remaining / lv_done ).
        DATA(lv_min) = lv_eta_secs DIV 60.
        DATA(lv_sec) = lv_eta_secs MOD 60.
        lv_eta = COND string(
          WHEN lv_min > 0 THEN | – est. { lv_min }m { lv_sec }s left|
          ELSE                 | – est. { lv_sec }s left| ).
      ENDIF.

      DATA(lv_msg)  = COND string(
        WHEN i_text IS NOT INITIAL THEN |{ i_text } ({ lv_done }/{ i_total }){ lv_eta }|
        ELSE                            |{ mv_title } ({ lv_done }/{ i_total }){ lv_eta }| ).
      CALL FUNCTION 'SAPGUI_PROGRESS_INDICATOR'
        EXPORTING percentage = lv_pct text = CONV char70( lv_msg ).
      mv_ts_last_bar = lv_now.
    ENDIF.

    " Threshold check: ask the user whether to keep going
    cl_abap_tstmp=>subtract(
      EXPORTING tstmp1 = lv_now tstmp2 = mv_ts_start
      RECEIVING r_secs = lv_secs ).
    IF lv_secs <= mv_threshold.
      RETURN.
    ENDIF.
    IF line_exists( mt_confirmed_keys[ table_line = mv_confirm_key ] ).
      GET TIME STAMP FIELD mv_ts_start.
      RETURN.
    ENDIF.

    DATA(lv_text) = COND string(
      WHEN i_remaining > 0 THEN |{ i_remaining } items remaining. Continue?|
      ELSE                      |Operation is taking a while. Continue?| ).
    DATA lv_answer TYPE c LENGTH 1.
    CALL FUNCTION 'POPUP_TO_CONFIRM'
      EXPORTING
        titlebar       = CONV char70( mv_title )
        text_question  = lv_text
        text_button_1  = 'Continue'
        text_button_2  = 'Stop'
        default_button = '2'
        start_column   = 60
        start_row      = 3
      IMPORTING
        answer         = lv_answer.
    IF lv_answer <> '1'.
      mv_stopped = abap_true.
      mv_stop_requested = abap_true.
      result     = abap_true.
      RETURN.
    ENDIF.
    INSERT mv_confirm_key INTO TABLE mt_confirmed_keys.
    GET TIME STAMP FIELD mv_ts_start.
  ENDMETHOD.

  METHOD was_stopped.
    result = mv_stopped.
  ENDMETHOD.

  METHOD reset_stop.
    mv_stop_requested = abap_false.
  ENDMETHOD.

  METHOD was_stop_requested.
    result = mv_stop_requested.
  ENDMETHOD.

ENDCLASS.
