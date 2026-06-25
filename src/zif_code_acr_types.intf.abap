interface ZIF_CODE_ACR_TYPES
  public .

  TYPES ty_approved TYPE HASHED TABLE OF string WITH UNIQUE KEY table_line.

  TYPES ty_action_code TYPE c LENGTH 1.

  TYPES:
    BEGIN OF ty_hunk_action,
      hunk_key      TYPE string,
      reviewer      TYPE syuname,
      reviewer_name TYPE ad_namtext,
      action        TYPE ty_action_code,
      changed_at    TYPE timestampl,
    END OF ty_hunk_action.
  TYPES ty_t_hunk_actions TYPE STANDARD TABLE OF ty_hunk_action WITH DEFAULT KEY.

  "! Decline notes: key = hunk key (OBJTYPE~OBJNAME~N), value = note text
  TYPES:
    BEGIN OF ty_decline_note,
      hunk_key TYPE string,
      note     TYPE string,
    END OF ty_decline_note.
  TYPES ty_t_decline_notes TYPE HASHED TABLE OF ty_decline_note WITH UNIQUE KEY hunk_key.

  TYPES:
    BEGIN OF ty_decline_msg,
      author      TYPE syuname,
      author_name TYPE ad_namtext,
      created_at  TYPE timestampl,
      is_decline  TYPE abap_bool,
      text        TYPE string,
    END OF ty_decline_msg.
  TYPES ty_t_decline_msgs TYPE STANDARD TABLE OF ty_decline_msg WITH DEFAULT KEY.

  TYPES:
    BEGIN OF ty_hunk_info,
      hunk_key        TYPE string,
      objtype         TYPE versobjtyp,
      obj_name        TYPE versobjnam,
      class_name      TYPE seoclsname,
      display_name    TYPE string,
      hunk_no         TYPE i,
      start_line      TYPE i,
      change_count    TYPE i,
      change_kind     TYPE string,
      author          TYPE versuser,
      author_name     TYPE ad_namtext,
      versno_new      TYPE versno,
      versno_old      TYPE versno,
      versno_new_text TYPE string,
      versno_old_text TYPE string,
      html            TYPE string,
      "! Retrofit warning text (non-initial = hunk diverges vs remote system)
      retrofit        TYPE string,
    END OF ty_hunk_info.
  TYPES ty_t_hunk_info TYPE HASHED TABLE OF ty_hunk_info WITH UNIQUE KEY hunk_key.

  "! Set of changed lines (|op|text|) used to cross-check retrofit hunks
  TYPES ty_review_lines TYPE HASHED TABLE OF string WITH UNIQUE KEY table_line.

  TYPES:
    BEGIN OF ty_hunk_thread,
      hunk_key        TYPE string,
      objtype         TYPE versobjtyp,
      obj_name        TYPE versobjnam,
      class_name      TYPE seoclsname,
      display_name    TYPE string,
      hunk_no         TYPE i,
      start_line      TYPE i,
      change_count    TYPE i,
      change_kind     TYPE string,
      versno_new      TYPE versno,
      versno_old      TYPE versno,
      versno_new_text TYPE string,
      versno_old_text TYPE string,
      html            TYPE string,
      messages        TYPE ty_t_decline_msgs,
    END OF ty_hunk_thread.
  TYPES ty_t_hunk_threads TYPE HASHED TABLE OF ty_hunk_thread WITH UNIQUE KEY hunk_key.

  TYPES:
    BEGIN OF ty_saved_thread,
      hunk_key        TYPE string,
      objtype         TYPE versobjtyp,
      obj_name        TYPE versobjnam,
      class_name      TYPE seoclsname,
      display_name    TYPE string,
      hunk_no         TYPE i,
      start_line      TYPE i,
      change_count    TYPE i,
      change_kind     TYPE string,
      author          TYPE versuser,
      author_name     TYPE ad_namtext,
      versno_new      TYPE versno,
      versno_old      TYPE versno,
      versno_new_text TYPE string,
      versno_old_text TYPE string,
      html            TYPE string,
      messages        TYPE ty_t_decline_msgs,
    END OF ty_saved_thread.
  TYPES ty_t_saved_threads TYPE STANDARD TABLE OF ty_saved_thread WITH DEFAULT KEY.

  TYPES:
    BEGIN OF ty_saved_key,
      hunk_key TYPE string,
    END OF ty_saved_key.
  TYPES ty_t_saved_keys TYPE STANDARD TABLE OF ty_saved_key WITH DEFAULT KEY.

  TYPES:
    BEGIN OF ty_saved_note,
      hunk_key TYPE string,
      note     TYPE string,
    END OF ty_saved_note.
  TYPES ty_t_saved_notes TYPE STANDARD TABLE OF ty_saved_note WITH DEFAULT KEY.

  TYPES:
    BEGIN OF ty_saved_user_state,
      reviewer      TYPE syuname,
      reviewer_name TYPE ad_namtext,
      saved_at      TYPE timestampl,
      approved      TYPE ty_t_saved_keys,
      declined      TYPE ty_t_saved_keys,
      notes         TYPE ty_t_saved_notes,
    END OF ty_saved_user_state.
  TYPES ty_t_saved_user_state TYPE STANDARD TABLE OF ty_saved_user_state WITH DEFAULT KEY.

  TYPES:
    BEGIN OF ty_saved_history,
      saved_at       TYPE timestampl,
      saved_by       TYPE syuname,
      saved_by_name  TYPE ad_namtext,
      approved_count TYPE i,
      declined_count TYPE i,
      note_count     TYPE i,
    END OF ty_saved_history.
  TYPES ty_t_saved_history TYPE STANDARD TABLE OF ty_saved_history WITH DEFAULT KEY.

  "! Per-instance cache for rendered diff HTML.
  TYPES:
    BEGIN OF ty_diff_cache_key,
      objtype     TYPE versobjtyp,
      objname     TYPE versobjnam,
      system_o    TYPE verssysnam,
      system_n    TYPE verssysnam,
      versno_o    TYPE versno,
      versno_n    TYPE versno,
      blame       TYPE abap_bool,
      two_pane    TYPE abap_bool,
      compact     TYPE abap_bool,
      debug       TYPE abap_bool,
      ignore_case   TYPE abap_bool,
      ignore_indent TYPE abap_bool,
    END OF ty_diff_cache_key.
  TYPES:
    BEGIN OF ty_diff_cache,
      key  TYPE ty_diff_cache_key,
      html TYPE string,
    END OF ty_diff_cache.
  TYPES ty_t_diff_cache TYPE HASHED TABLE OF ty_diff_cache WITH UNIQUE KEY key.

  "! Persisted review diff data. HTML is derived from this at load/render time.
  TYPES:
    BEGIN OF ty_diff_data_key,
      objtype       TYPE versobjtyp,
      objname       TYPE versobjnam,
      versno_o      TYPE versno,
      versno_n      TYPE versno,
      blame         TYPE abap_bool,
      ignore_case   TYPE abap_bool,
      ignore_indent TYPE abap_bool,
    END OF ty_diff_data_key.
  TYPES:
    BEGIN OF ty_diff_data,
      key           TYPE ty_diff_data_key,
      diff          TYPE zif_code_popup_types=>ty_t_diff,
      blame_map     TYPE zif_code_popup_types=>ty_blame_map,
      blame_deleted TYPE zif_code_popup_types=>ty_blame_map,
      huge_source   TYPE abap_bool,
      title         TYPE string,
      meta          TYPE string,
      is_created    TYPE abap_bool,
      "! Marks the remote retrofit (moving-violation) diff, regenerated on the fly
      retrofit      TYPE abap_bool,
    END OF ty_diff_data.
  TYPES ty_t_diff_data TYPE HASHED TABLE OF ty_diff_data WITH UNIQUE KEY key.

  "! Per-author change contribution inside one object diff
  TYPES:
    BEGIN OF ty_author_stats,
      author      TYPE versuser,
      author_name TYPE ad_namtext,
      ins_count   TYPE i,
      del_count   TYPE i,
      mod_count   TYPE i,
      hunk_count  TYPE i,
    END OF ty_author_stats.
  TYPES ty_t_author_stats TYPE STANDARD TABLE OF ty_author_stats WITH DEFAULT KEY.

  "! Per-reviewer action totals for the report header
  TYPES:
    BEGIN OF ty_reviewer_stats,
      reviewer      TYPE syuname,
      reviewer_name TYPE ad_namtext,
      appr_count    TYPE i,
      decl_count    TYPE i,
      total_count   TYPE i,
      saved_at      TYPE timestampl,
    END OF ty_reviewer_stats.
  TYPES ty_t_reviewer_stats TYPE STANDARD TABLE OF ty_reviewer_stats WITH DEFAULT KEY.

  "! Statistics for one changed object: version pair, counts, blame breakdown
  TYPES:
    BEGIN OF ty_obj_stats,
      objtype     TYPE versobjtyp,
      class_name  TYPE seoclsname,   " parent class for METH / CPUB / CPRO / CPRI / CINC
      obj_name    TYPE versobjnam,
      versno_new  TYPE versno,
      versno_old  TYPE versno,
      author      TYPE versuser,
      author_name TYPE ad_namtext,
      datum       TYPE versdate,
      zeit        TYPE verstime,
      ins_count   TYPE i,
      del_count   TYPE i,
      mod_count   TYPE i,
      hunk_count  TYPE i,
      hunk_ins    TYPE i,   " blocks with only added lines
      hunk_mod    TYPE i,   " blocks with both added and deleted lines (modified)
      hunk_del    TYPE i,   " blocks with only deleted lines
      display_name  TYPE string,
      bt_authors    TYPE ty_t_author_stats,
      is_created    TYPE abap_bool,   " abap_true = object is brand-new (no prior version)
    END OF ty_obj_stats.
  TYPES ty_t_obj_stats TYPE STANDARD TABLE OF ty_obj_stats WITH DEFAULT KEY.

  TYPES:
    BEGIN OF ty_saved_payload,
      schema_version TYPE i,
      trkorr         TYPE trkorr,
      last_saved_at  TYPE timestampl,
      last_saved_by  TYPE syuname,
      obj_stats      TYPE ty_t_obj_stats,
      hunks          TYPE ty_t_hunk_info,
      diff_data      TYPE ty_t_diff_data,
      hunk_actions   TYPE ty_t_hunk_actions,
      user_states    TYPE ty_t_saved_user_state,
      threads        TYPE ty_t_saved_threads,
      history        TYPE ty_t_saved_history,
    END OF ty_saved_payload.


endinterface.
