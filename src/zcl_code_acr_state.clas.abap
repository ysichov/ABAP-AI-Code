CLASS zcl_code_acr_state DEFINITION
  PUBLIC
  FINAL
  CREATE PRIVATE.

  PUBLIC SECTION.
    CLASS-METHODS format_timestamp
      IMPORTING
        !iv_timestamp   TYPE timestampl
      RETURNING
        VALUE(result)   TYPE string.

    CLASS-METHODS set_hunk_action
      IMPORTING
        !iv_hunk_key     TYPE string
        !iv_action       TYPE zif_code_acr_types=>ty_action_code
      CHANGING
        !ct_hunk_actions TYPE zif_code_acr_types=>ty_t_hunk_actions.

    CLASS-METHODS clear_hunk_action
      IMPORTING
        !iv_hunk_key     TYPE string
      CHANGING
        !ct_hunk_actions TYPE zif_code_acr_types=>ty_t_hunk_actions.

    CLASS-METHODS get_hunk_global_action
      IMPORTING
        !iv_hunk_key     TYPE string
        !it_hunk_actions TYPE zif_code_acr_types=>ty_t_hunk_actions
      RETURNING
        VALUE(result)    TYPE zif_code_acr_types=>ty_action_code.

    CLASS-METHODS sanitize_review_state
      IMPORTING
        !it_hunk_info    TYPE zif_code_acr_types=>ty_t_hunk_info
      CHANGING
        !ct_approved     TYPE zif_code_acr_types=>ty_approved
        !ct_declined     TYPE zif_code_acr_types=>ty_approved
        !ct_hunk_actions TYPE zif_code_acr_types=>ty_t_hunk_actions.

    CLASS-METHODS is_own_hunk
      IMPORTING
        !iv_hunk_key   TYPE string
        !it_hunk_info  TYPE zif_code_acr_types=>ty_t_hunk_info
      RETURNING
        VALUE(result)  TYPE abap_bool.

    CLASS-METHODS get_last_own_comment
      IMPORTING
        !iv_hunk_key      TYPE string
        !it_hunk_threads  TYPE zif_code_acr_types=>ty_t_hunk_threads
      RETURNING
        VALUE(result)     TYPE string.

    CLASS-METHODS get_reviewer_stats
      IMPORTING
        is_payload      TYPE zif_code_acr_types=>ty_saved_payload
        it_hunk_info    TYPE zif_code_acr_types=>ty_t_hunk_info
        it_approved     TYPE zif_code_acr_types=>ty_approved
        it_declined     TYPE zif_code_acr_types=>ty_approved
        it_hunk_threads TYPE zif_code_acr_types=>ty_t_hunk_threads
      RETURNING
        VALUE(result)   TYPE zif_code_acr_types=>ty_t_reviewer_stats.

    CLASS-METHODS apply_saved_payload
      IMPORTING
        is_payload       TYPE zif_code_acr_types=>ty_saved_payload
      CHANGING
        ct_obj_stats     TYPE zif_code_acr_types=>ty_t_obj_stats
        ct_hunk_info     TYPE zif_code_acr_types=>ty_t_hunk_info
        ct_diff_cache    TYPE zif_code_acr_types=>ty_t_diff_cache
        ct_diff_data     TYPE zif_code_acr_types=>ty_t_diff_data
        ct_approved      TYPE zif_code_acr_types=>ty_approved
        ct_declined      TYPE zif_code_acr_types=>ty_approved
        ct_decline_notes TYPE zif_code_acr_types=>ty_t_decline_notes
        ct_hunk_threads  TYPE zif_code_acr_types=>ty_t_hunk_threads
        ct_hunk_actions  TYPE zif_code_acr_types=>ty_t_hunk_actions.

    CLASS-METHODS collect_report_status
      IMPORTING
        is_payload    TYPE zif_code_acr_types=>ty_saved_payload
        it_hunk_info  TYPE zif_code_acr_types=>ty_t_hunk_info
        it_approved   TYPE zif_code_acr_types=>ty_approved
        it_declined   TYPE zif_code_acr_types=>ty_approved
      EXPORTING
        et_approved   TYPE zif_code_acr_types=>ty_approved
        et_declined   TYPE zif_code_acr_types=>ty_approved.

    CLASS-METHODS build_save_payload
      IMPORTING
        is_existing_payload TYPE zif_code_acr_types=>ty_saved_payload
        iv_trkorr           TYPE trkorr
        it_obj_stats        TYPE zif_code_acr_types=>ty_t_obj_stats
        it_hunk_info        TYPE zif_code_acr_types=>ty_t_hunk_info
        it_diff_cache       TYPE zif_code_acr_types=>ty_t_diff_cache
        it_diff_data        TYPE zif_code_acr_types=>ty_t_diff_data
        it_hunk_actions     TYPE zif_code_acr_types=>ty_t_hunk_actions
        it_approved         TYPE zif_code_acr_types=>ty_approved
        it_declined         TYPE zif_code_acr_types=>ty_approved
        it_decline_notes    TYPE zif_code_acr_types=>ty_t_decline_notes
        it_hunk_threads     TYPE zif_code_acr_types=>ty_t_hunk_threads
      RETURNING
        VALUE(result)       TYPE zif_code_acr_types=>ty_saved_payload.

  PRIVATE SECTION.
    CLASS-METHODS hydrate_hunk_html
      IMPORTING
        it_diff_data  TYPE zif_code_acr_types=>ty_t_diff_data
      CHANGING
        ct_hunk_info  TYPE zif_code_acr_types=>ty_t_hunk_info.
ENDCLASS.


CLASS zcl_code_acr_state IMPLEMENTATION.

  METHOD format_timestamp.
    CHECK iv_timestamp IS NOT INITIAL.
    DATA lv_date TYPE d.
    DATA lv_time TYPE t.
    CONVERT TIME STAMP iv_timestamp TIME ZONE sy-zonlo
      INTO DATE lv_date TIME lv_time.
    result = |{ lv_date+6(2) }.{ lv_date+4(2) }.{ lv_date+2(2) } { lv_time(5) }|.
  ENDMETHOD.


  METHOD set_hunk_action.
    DATA lv_ts TYPE timestampl.
    GET TIME STAMP FIELD lv_ts.
    DELETE ct_hunk_actions WHERE hunk_key = iv_hunk_key AND reviewer = sy-uname.
    APPEND VALUE zif_code_acr_types=>ty_hunk_action(
      hunk_key      = iv_hunk_key
      reviewer      = sy-uname
      reviewer_name = zcl_code_popup_data=>get_user_name( sy-uname )
      action        = iv_action
      changed_at    = lv_ts ) TO ct_hunk_actions.
  ENDMETHOD.


  METHOD clear_hunk_action.
    DELETE ct_hunk_actions WHERE hunk_key = iv_hunk_key AND reviewer = sy-uname.
  ENDMETHOD.


  METHOD get_hunk_global_action.
    DATA ls_action TYPE zif_code_acr_types=>ty_hunk_action.
    LOOP AT it_hunk_actions INTO DATA(ls_action_cur)
      WHERE hunk_key = iv_hunk_key.
      IF ls_action IS INITIAL OR ls_action_cur-changed_at > ls_action-changed_at.
        ls_action = ls_action_cur.
      ENDIF.
    ENDLOOP.
    result = ls_action-action.
  ENDMETHOD.


  METHOD sanitize_review_state.
    CHECK it_hunk_info IS NOT INITIAL.

    LOOP AT ct_approved INTO DATA(lv_approved_key).
      IF NOT line_exists( it_hunk_info[ hunk_key = lv_approved_key ] ).
        DELETE TABLE ct_approved FROM lv_approved_key.
      ENDIF.
    ENDLOOP.

    LOOP AT ct_declined INTO DATA(lv_declined_key).
      IF NOT line_exists( it_hunk_info[ hunk_key = lv_declined_key ] ).
        DELETE TABLE ct_declined FROM lv_declined_key.
      ELSEIF line_exists( ct_approved[ table_line = lv_declined_key ] ).
        DELETE TABLE ct_declined FROM lv_declined_key.
      ENDIF.
    ENDLOOP.

    LOOP AT ct_hunk_actions INTO DATA(ls_action_key).
      IF NOT line_exists( it_hunk_info[ hunk_key = ls_action_key-hunk_key ] ).
        DELETE ct_hunk_actions WHERE hunk_key = ls_action_key-hunk_key.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.


  METHOD is_own_hunk.
    result = abap_false.
    READ TABLE it_hunk_info INTO DATA(ls_hunk)
      WITH TABLE KEY hunk_key = iv_hunk_key.
    IF sy-subrc = 0 AND ls_hunk-author = sy-uname AND sy-uname <> 'DEVELOPER'.
      result = abap_true.
    ELSEIF sy-subrc = 0 AND ls_hunk-author IS INITIAL AND ls_hunk-html CS sy-uname.
      result = abap_true.
    ENDIF.
  ENDMETHOD.


  METHOD get_last_own_comment.
    READ TABLE it_hunk_threads INTO DATA(ls_thread)
      WITH TABLE KEY hunk_key = iv_hunk_key.
    CHECK sy-subrc = 0.

    DATA(lv_idx) = lines( ls_thread-messages ).
    WHILE lv_idx > 0.
      READ TABLE ls_thread-messages INTO DATA(ls_msg) INDEX lv_idx.
      IF sy-subrc = 0
         AND ls_msg-author = sy-uname
         AND ls_msg-text IS NOT INITIAL.
        result = ls_msg-text.
        RETURN.
      ENDIF.
      lv_idx = lv_idx - 1.
    ENDWHILE.
  ENDMETHOD.


  METHOD get_reviewer_stats.
    LOOP AT is_payload-user_states INTO DATA(ls_user_state).
      DATA lv_appr_saved TYPE i.
      DATA lv_decl_saved TYPE i.
      CLEAR: lv_appr_saved, lv_decl_saved.
      LOOP AT ls_user_state-approved INTO DATA(ls_saved_appr_key).
        IF it_hunk_info IS INITIAL
           OR line_exists( it_hunk_info[ hunk_key = ls_saved_appr_key-hunk_key ] ).
          lv_appr_saved = lv_appr_saved + 1.
        ENDIF.
      ENDLOOP.
      LOOP AT ls_user_state-declined INTO DATA(ls_saved_decl_key).
        IF it_hunk_info IS INITIAL
           OR line_exists( it_hunk_info[ hunk_key = ls_saved_decl_key-hunk_key ] ).
          lv_decl_saved = lv_decl_saved + 1.
        ENDIF.
      ENDLOOP.
      CHECK lv_appr_saved > 0 OR lv_decl_saved > 0.
      APPEND VALUE zif_code_acr_types=>ty_reviewer_stats(
        reviewer      = ls_user_state-reviewer
        reviewer_name = ls_user_state-reviewer_name
        appr_count    = lv_appr_saved
        decl_count    = lv_decl_saved
        total_count   = lv_appr_saved + lv_decl_saved
        saved_at      = ls_user_state-saved_at ) TO result.
    ENDLOOP.

    DATA(lv_appr_cur) = lines( it_approved ).
    DATA(lv_decl_cur) = lines( it_declined ).
    IF lv_appr_cur > 0 OR lv_decl_cur > 0.
      READ TABLE result ASSIGNING FIELD-SYMBOL(<rev>)
        WITH KEY reviewer = sy-uname.
      IF sy-subrc <> 0.
        APPEND VALUE zif_code_acr_types=>ty_reviewer_stats(
          reviewer      = sy-uname
          reviewer_name = zcl_code_popup_data=>get_user_name( sy-uname ) ) TO result.
        READ TABLE result ASSIGNING <rev> WITH KEY reviewer = sy-uname.
      ENDIF.
      <rev>-appr_count = lv_appr_cur.
      <rev>-decl_count = lv_decl_cur.
      <rev>-total_count = lv_appr_cur + lv_decl_cur.
    ENDIF.

    LOOP AT it_hunk_threads INTO DATA(ls_thread_cur).
      READ TABLE it_hunk_info INTO DATA(ls_hunk_cur)
        WITH TABLE KEY hunk_key = ls_thread_cur-hunk_key.
      LOOP AT ls_thread_cur-messages INTO DATA(ls_msg_cur).
        CHECK ls_msg_cur-author IS NOT INITIAL.
        IF sy-subrc = 0 AND ls_hunk_cur-author = ls_msg_cur-author.
          CONTINUE.
        ENDIF.
        READ TABLE result ASSIGNING <rev>
          WITH KEY reviewer = ls_msg_cur-author.
        IF sy-subrc <> 0.
          APPEND VALUE zif_code_acr_types=>ty_reviewer_stats(
            reviewer      = ls_msg_cur-author
            reviewer_name = ls_msg_cur-author_name ) TO result.
          READ TABLE result ASSIGNING <rev> WITH KEY reviewer = ls_msg_cur-author.
        ENDIF.
        IF <rev>-total_count = 0.
          <rev>-total_count = 1.
        ENDIF.
      ENDLOOP.
    ENDLOOP.
  ENDMETHOD.


  METHOD apply_saved_payload.
    CLEAR: ct_approved, ct_declined, ct_decline_notes, ct_hunk_threads, ct_hunk_actions.

    IF ct_obj_stats IS INITIAL AND is_payload-obj_stats IS NOT INITIAL.
      ct_obj_stats = is_payload-obj_stats.
    ENDIF.
    IF ct_hunk_info IS INITIAL AND is_payload-hunks IS NOT INITIAL.
      ct_hunk_info = is_payload-hunks.
    ENDIF.
    IF ct_diff_data IS INITIAL AND is_payload-diff_data IS NOT INITIAL.
      ct_diff_data = is_payload-diff_data.
    ENDIF.
    CLEAR ct_diff_cache.
    hydrate_hunk_html(
      EXPORTING
        it_diff_data = ct_diff_data
      CHANGING
        ct_hunk_info = ct_hunk_info ).
    ct_hunk_actions = is_payload-hunk_actions.

    LOOP AT is_payload-threads INTO DATA(ls_saved_thread).
      DATA(ls_thread) = VALUE zif_code_acr_types=>ty_hunk_thread(
        hunk_key     = ls_saved_thread-hunk_key
        objtype      = ls_saved_thread-objtype
        obj_name     = ls_saved_thread-obj_name
        class_name   = ls_saved_thread-class_name
        display_name = ls_saved_thread-display_name
        hunk_no      = ls_saved_thread-hunk_no
        start_line   = ls_saved_thread-start_line
        change_count = ls_saved_thread-change_count
        change_kind  = ls_saved_thread-change_kind
        html         = ls_saved_thread-html
        messages     = ls_saved_thread-messages ).
      READ TABLE ct_hunk_info INTO DATA(ls_hunk_info_cur)
        WITH TABLE KEY hunk_key = ls_saved_thread-hunk_key.
      IF sy-subrc = 0.
        ls_thread-objtype      = ls_hunk_info_cur-objtype.
        ls_thread-obj_name     = ls_hunk_info_cur-obj_name.
        ls_thread-class_name   = ls_hunk_info_cur-class_name.
        ls_thread-display_name = ls_hunk_info_cur-display_name.
        ls_thread-hunk_no      = ls_hunk_info_cur-hunk_no.
        ls_thread-start_line   = ls_hunk_info_cur-start_line.
        ls_thread-change_count = ls_hunk_info_cur-change_count.
        ls_thread-change_kind  = ls_hunk_info_cur-change_kind.
        ls_thread-versno_new   = ls_hunk_info_cur-versno_new.
        ls_thread-versno_old   = ls_hunk_info_cur-versno_old.
        ls_thread-versno_new_text = ls_hunk_info_cur-versno_new_text.
        ls_thread-versno_old_text = ls_hunk_info_cur-versno_old_text.
        ls_thread-html         = ls_hunk_info_cur-html.
      ENDIF.
      IF NOT line_exists( ct_hunk_info[ hunk_key = ls_saved_thread-hunk_key ] )
         AND ls_saved_thread-hunk_key NP 'AI_SUMMARY~*'.
        INSERT VALUE zif_code_acr_types=>ty_hunk_info(
          hunk_key     = ls_saved_thread-hunk_key
          objtype      = ls_saved_thread-objtype
          obj_name     = ls_saved_thread-obj_name
          class_name   = ls_saved_thread-class_name
          display_name = ls_saved_thread-display_name
          hunk_no      = ls_saved_thread-hunk_no
          start_line   = ls_saved_thread-start_line
          change_count = ls_saved_thread-change_count
          change_kind  = ls_saved_thread-change_kind
          author       = ls_saved_thread-author
          author_name  = ls_saved_thread-author_name
          versno_new   = ls_saved_thread-versno_new
          versno_old   = ls_saved_thread-versno_old
          versno_new_text = ls_saved_thread-versno_new_text
          versno_old_text = ls_saved_thread-versno_old_text
          html         = ls_saved_thread-html ) INTO TABLE ct_hunk_info.
      ENDIF.
      INSERT ls_thread INTO TABLE ct_hunk_threads.
    ENDLOOP.

    LOOP AT is_payload-user_states INTO DATA(ls_action_state).
      LOOP AT ls_action_state-approved INTO DATA(ls_action_approved).
        IF ( ct_hunk_info IS INITIAL
             OR line_exists( ct_hunk_info[ hunk_key = ls_action_approved-hunk_key ] ) )
           AND NOT line_exists( ct_hunk_actions[
             hunk_key = ls_action_approved-hunk_key reviewer = ls_action_state-reviewer action = 'A' ] ).
          APPEND VALUE zif_code_acr_types=>ty_hunk_action(
            hunk_key      = ls_action_approved-hunk_key
            reviewer      = ls_action_state-reviewer
            reviewer_name = ls_action_state-reviewer_name
            action        = 'A'
            changed_at    = ls_action_state-saved_at ) TO ct_hunk_actions.
        ENDIF.
      ENDLOOP.
      LOOP AT ls_action_state-declined INTO DATA(ls_action_declined).
        IF ( ct_hunk_info IS INITIAL
             OR line_exists( ct_hunk_info[ hunk_key = ls_action_declined-hunk_key ] ) )
           AND NOT line_exists( ct_hunk_actions[
             hunk_key = ls_action_declined-hunk_key reviewer = ls_action_state-reviewer action = 'D' ] ).
          APPEND VALUE zif_code_acr_types=>ty_hunk_action(
            hunk_key      = ls_action_declined-hunk_key
            reviewer      = ls_action_state-reviewer
            reviewer_name = ls_action_state-reviewer_name
            action        = 'D'
            changed_at    = ls_action_state-saved_at ) TO ct_hunk_actions.
        ENDIF.
      ENDLOOP.
    ENDLOOP.

    READ TABLE is_payload-user_states INTO DATA(ls_user_state)
      WITH KEY reviewer = sy-uname.
    IF sy-subrc = 0.
      LOOP AT ls_user_state-approved INTO DATA(ls_approved_key).
        INSERT ls_approved_key-hunk_key INTO TABLE ct_approved.
        IF NOT line_exists( ct_hunk_actions[
          hunk_key = ls_approved_key-hunk_key reviewer = ls_user_state-reviewer action = 'A' ] ).
          APPEND VALUE zif_code_acr_types=>ty_hunk_action(
            hunk_key      = ls_approved_key-hunk_key
            reviewer      = ls_user_state-reviewer
            reviewer_name = ls_user_state-reviewer_name
            action        = 'A'
            changed_at    = ls_user_state-saved_at ) TO ct_hunk_actions.
        ENDIF.
      ENDLOOP.
      LOOP AT ls_user_state-declined INTO DATA(ls_declined_key).
        INSERT ls_declined_key-hunk_key INTO TABLE ct_declined.
        IF NOT line_exists( ct_hunk_actions[
          hunk_key = ls_declined_key-hunk_key reviewer = ls_user_state-reviewer action = 'D' ] ).
          APPEND VALUE zif_code_acr_types=>ty_hunk_action(
            hunk_key      = ls_declined_key-hunk_key
            reviewer      = ls_user_state-reviewer
            reviewer_name = ls_user_state-reviewer_name
            action        = 'D'
            changed_at    = ls_user_state-saved_at ) TO ct_hunk_actions.
        ENDIF.
      ENDLOOP.
      LOOP AT ls_user_state-notes INTO DATA(ls_saved_note).
        INSERT VALUE zif_code_acr_types=>ty_decline_note(
          hunk_key = ls_saved_note-hunk_key
          note     = ls_saved_note-note ) INTO TABLE ct_decline_notes.
      ENDLOOP.
    ENDIF.

    sanitize_review_state(
      EXPORTING
        it_hunk_info    = ct_hunk_info
      CHANGING
        ct_approved     = ct_approved
        ct_declined     = ct_declined
        ct_hunk_actions = ct_hunk_actions ).
  ENDMETHOD.


  METHOD hydrate_hunk_html.
    LOOP AT it_diff_data INTO DATA(ls_diff_data).
      DATA(lv_full_html) = zcl_code_popup_html=>diff_to_html(
        it_diff          = ls_diff_data-diff
        i_title          = ls_diff_data-title
        i_meta           = ls_diff_data-meta
        i_two_pane       = abap_true
        i_compact        = abap_false
        i_plain          = ls_diff_data-huge_source
        i_ignore_case    = ls_diff_data-key-ignore_case
        i_code_review    = abap_true
        it_blame         = ls_diff_data-blame_map
        it_blame_deleted = ls_diff_data-blame_deleted ).
      DATA(lt_hunk_html) = zcl_code_acr_hunk_html=>collect_rows(
        it_diff          = ls_diff_data-diff
        iv_full_html     = lv_full_html
        iv_title         = ls_diff_data-title
        iv_meta          = ls_diff_data-meta
        iv_two_pane      = abap_true
        iv_plain         = ls_diff_data-huge_source
        iv_ignore_case   = ls_diff_data-key-ignore_case
        iv_is_created    = ls_diff_data-is_created
        it_blame         = ls_diff_data-blame_map
        it_blame_deleted = ls_diff_data-blame_deleted ).

      LOOP AT ct_hunk_info ASSIGNING FIELD-SYMBOL(<hunk>)
        WHERE objtype = ls_diff_data-key-objtype
          AND obj_name = ls_diff_data-key-objname.
        READ TABLE lt_hunk_html INTO DATA(lv_hunk_html) INDEX <hunk>-hunk_no.
        IF sy-subrc = 0.
          <hunk>-html = lv_hunk_html.
        ENDIF.
      ENDLOOP.
    ENDLOOP.
  ENDMETHOD.


  METHOD collect_report_status.
    CLEAR: et_approved, et_declined.

    LOOP AT is_payload-user_states INTO DATA(ls_user_state).
      LOOP AT ls_user_state-approved INTO DATA(ls_saved_approved).
        IF it_hunk_info IS INITIAL
           OR line_exists( it_hunk_info[ hunk_key = ls_saved_approved-hunk_key ] ).
          INSERT ls_saved_approved-hunk_key INTO TABLE et_approved.
        ENDIF.
      ENDLOOP.
      LOOP AT ls_user_state-declined INTO DATA(ls_saved_declined).
        IF it_hunk_info IS INITIAL
           OR line_exists( it_hunk_info[ hunk_key = ls_saved_declined-hunk_key ] ).
          INSERT ls_saved_declined-hunk_key INTO TABLE et_declined.
        ENDIF.
      ENDLOOP.
    ENDLOOP.

    LOOP AT it_approved INTO DATA(lv_approved_key).
      INSERT lv_approved_key INTO TABLE et_approved.
    ENDLOOP.
    LOOP AT it_declined INTO DATA(lv_declined_key).
      INSERT lv_declined_key INTO TABLE et_declined.
    ENDLOOP.

    IF it_hunk_info IS NOT INITIAL.
      LOOP AT et_approved INTO lv_approved_key.
        IF NOT line_exists( it_hunk_info[ hunk_key = lv_approved_key ] ).
          DELETE TABLE et_approved FROM lv_approved_key.
        ENDIF.
      ENDLOOP.
      LOOP AT et_declined INTO lv_declined_key.
        IF NOT line_exists( it_hunk_info[ hunk_key = lv_declined_key ] )
           OR line_exists( et_approved[ table_line = lv_declined_key ] ).
          DELETE TABLE et_declined FROM lv_declined_key.
        ENDIF.
      ENDLOOP.
    ENDIF.
  ENDMETHOD.


  METHOD build_save_payload.
    DATA lv_saved_at TYPE timestampl.
    GET TIME STAMP FIELD lv_saved_at.
    DATA(lv_user_name) = zcl_code_popup_data=>get_user_name( sy-uname ).

    result = is_existing_payload.
    result-schema_version = 2.
    result-trkorr = iv_trkorr.
    result-last_saved_at = lv_saved_at.
    result-last_saved_by = sy-uname.
    result-obj_stats = it_obj_stats.
    result-hunks = it_hunk_info.
    LOOP AT result-hunks ASSIGNING FIELD-SYMBOL(<saved_hunk>).
      CLEAR <saved_hunk>-html.
    ENDLOOP.
    result-diff_data = it_diff_data.
    result-hunk_actions = it_hunk_actions.

    DATA(ls_user_state_new) = VALUE zif_code_acr_types=>ty_saved_user_state(
      reviewer      = sy-uname
      reviewer_name = lv_user_name
      saved_at      = lv_saved_at ).

    LOOP AT it_approved INTO DATA(lv_approved_key).
      APPEND VALUE zif_code_acr_types=>ty_saved_key( hunk_key = lv_approved_key ) TO ls_user_state_new-approved.
    ENDLOOP.
    LOOP AT it_declined INTO DATA(lv_declined_key).
      APPEND VALUE zif_code_acr_types=>ty_saved_key( hunk_key = lv_declined_key ) TO ls_user_state_new-declined.
    ENDLOOP.
    LOOP AT it_decline_notes INTO DATA(ls_note_cur).
      APPEND VALUE zif_code_acr_types=>ty_saved_note(
        hunk_key = ls_note_cur-hunk_key
        note     = ls_note_cur-note ) TO ls_user_state_new-notes.
    ENDLOOP.

    DELETE result-user_states WHERE reviewer = sy-uname.
    APPEND ls_user_state_new TO result-user_states.

    LOOP AT it_hunk_threads INTO DATA(ls_thread_cur).
      DATA(ls_thread_to_save) = VALUE zif_code_acr_types=>ty_saved_thread(
        hunk_key     = ls_thread_cur-hunk_key
        objtype      = ls_thread_cur-objtype
        obj_name     = ls_thread_cur-obj_name
        class_name   = ls_thread_cur-class_name
        display_name = ls_thread_cur-display_name
        hunk_no      = ls_thread_cur-hunk_no
        start_line   = ls_thread_cur-start_line
        change_count = ls_thread_cur-change_count
        change_kind  = ls_thread_cur-change_kind
        versno_new   = COND #(
          WHEN line_exists( it_hunk_info[ hunk_key = ls_thread_cur-hunk_key ] )
          THEN it_hunk_info[ hunk_key = ls_thread_cur-hunk_key ]-versno_new
          ELSE ls_thread_cur-versno_new )
        versno_old   = COND #(
          WHEN line_exists( it_hunk_info[ hunk_key = ls_thread_cur-hunk_key ] )
          THEN it_hunk_info[ hunk_key = ls_thread_cur-hunk_key ]-versno_old
          ELSE ls_thread_cur-versno_old )
        versno_new_text = COND #(
          WHEN line_exists( it_hunk_info[ hunk_key = ls_thread_cur-hunk_key ] )
          THEN it_hunk_info[ hunk_key = ls_thread_cur-hunk_key ]-versno_new_text
          ELSE ls_thread_cur-versno_new_text )
        versno_old_text = COND #(
          WHEN line_exists( it_hunk_info[ hunk_key = ls_thread_cur-hunk_key ] )
          THEN it_hunk_info[ hunk_key = ls_thread_cur-hunk_key ]-versno_old_text
          ELSE ls_thread_cur-versno_old_text )
        author       = COND #(
          WHEN line_exists( it_hunk_info[ hunk_key = ls_thread_cur-hunk_key ] )
          THEN it_hunk_info[ hunk_key = ls_thread_cur-hunk_key ]-author )
        author_name  = COND #(
          WHEN line_exists( it_hunk_info[ hunk_key = ls_thread_cur-hunk_key ] )
          THEN it_hunk_info[ hunk_key = ls_thread_cur-hunk_key ]-author_name )
        messages     = ls_thread_cur-messages ).

      READ TABLE result-threads ASSIGNING FIELD-SYMBOL(<ls_thread_saved>)
        WITH KEY hunk_key = ls_thread_cur-hunk_key.
      IF sy-subrc <> 0.
        APPEND ls_thread_to_save TO result-threads.
        CONTINUE.
      ENDIF.

      <ls_thread_saved>-objtype      = ls_thread_to_save-objtype.
      <ls_thread_saved>-obj_name     = ls_thread_to_save-obj_name.
      <ls_thread_saved>-class_name   = ls_thread_to_save-class_name.
      <ls_thread_saved>-display_name = ls_thread_to_save-display_name.
      <ls_thread_saved>-hunk_no      = ls_thread_to_save-hunk_no.
      <ls_thread_saved>-start_line   = ls_thread_to_save-start_line.
      <ls_thread_saved>-change_count = ls_thread_to_save-change_count.
      <ls_thread_saved>-change_kind  = ls_thread_to_save-change_kind.
      <ls_thread_saved>-author       = ls_thread_to_save-author.
      <ls_thread_saved>-author_name  = ls_thread_to_save-author_name.
      CLEAR <ls_thread_saved>-html.

      LOOP AT ls_thread_cur-messages INTO DATA(ls_msg_cur).
        READ TABLE <ls_thread_saved>-messages TRANSPORTING NO FIELDS
          WITH KEY author = ls_msg_cur-author
                   created_at = ls_msg_cur-created_at
                   text = ls_msg_cur-text.
        IF sy-subrc <> 0.
          APPEND ls_msg_cur TO <ls_thread_saved>-messages.
        ENDIF.
      ENDLOOP.
    ENDLOOP.

    LOOP AT result-threads ASSIGNING FIELD-SYMBOL(<saved_thread>).
      CLEAR <saved_thread>-html.
    ENDLOOP.

    APPEND VALUE zif_code_acr_types=>ty_saved_history(
      saved_at       = lv_saved_at
      saved_by       = sy-uname
      saved_by_name  = lv_user_name
      approved_count = lines( it_approved )
      declined_count = lines( it_declined )
      note_count     = lines( it_decline_notes ) ) TO result-history.
  ENDMETHOD.

ENDCLASS.
