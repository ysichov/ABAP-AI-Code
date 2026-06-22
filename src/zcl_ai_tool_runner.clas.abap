CLASS zcl_ai_tool_runner DEFINITION
  PUBLIC
  CREATE PUBLIC.

  PUBLIC SECTION.
    CONSTANTS c_max_iterations TYPE i VALUE 8.

    METHODS constructor
      IMPORTING
        !io_llm        TYPE REF TO zcl_abapai_llm_client
        !io_context    TYPE REF TO zcl_ai_tool_context
        !io_prompts    TYPE REF TO zcl_ai_agents_prompts OPTIONAL
        !io_ui         TYPE REF TO zcl_code_popup2 OPTIONAL
        !i_log_path    TYPE string OPTIONAL
        !i_provider    TYPE string OPTIONAL.

    " Agentic loop: LLM -> tool_calls -> execute -> results back -> LLM ...
    " Ends when the LLM answers without tool calls or c_max_iterations is hit.
    METHODS run
      IMPORTING
        !i_prompt        TYPE string
      RETURNING VALUE(rv_answer) TYPE string.

    " Access to the logged messages (for History popup, logging, etc.)
    METHODS get_messages
      RETURNING VALUE(ro_messages) TYPE REF TO zcl_ai_messages.

    " Reset conversation history (new session)
    METHODS clear_session.

    " True when the last run( ) launched an interactive diff code-review. The
    " caller must then NOT overwrite the answer panel - the diff is already shown
    " there and the save happens later via the diff toolbar (approve/decline).
    METHODS is_review_pending
      RETURNING VALUE(rv_pending) TYPE abap_bool.

    " Progress panel (middle pane): same step log as the legacy runner
    METHODS set_html_viewer
      IMPORTING
        !io_viewer TYPE REF TO cl_gui_html_viewer.

    " Single instrumented entry point for a tool's OWN (sub-agent) LLM call.
    " Tools must route through here (via zcl_ai_tool_context=>ask) instead of
    " calling the raw client, so the sub-call is shown in the progress panel,
    " logged and added to the running token totals - exactly like the
    " orchestrator's own calls. This keeps every tool (current and future)
    " visible to the orchestrator with no per-tool bookkeeping.
    METHODS agent_ask
      IMPORTING
        !i_label         TYPE string OPTIONAL
        !i_prompt        TYPE string
        !i_system_prompt TYPE string OPTIONAL
      RETURNING VALUE(rv_answer) TYPE string.

    DATA mv_session_num TYPE i.

  PROTECTED SECTION.
  PRIVATE SECTION.
    TYPES:
      BEGIN OF ty_step,
        text        TYPE string,
        agent       TYPE string,
        prompt_type TYPE string,
        done        TYPE abap_bool,
        is_llm      TYPE abap_bool,
        seconds     TYPE i,
        tok_in      TYPE i,
        tok_out     TYPE i,
        tok_cached  TYPE i,
      END OF ty_step,
      tt_steps TYPE STANDARD TABLE OF ty_step WITH NON-UNIQUE DEFAULT KEY.

    DATA mo_llm      TYPE REF TO zcl_abapai_llm_client.
    DATA mo_context  TYPE REF TO zcl_ai_tool_context.
    DATA mo_prompts  TYPE REF TO zcl_ai_agents_prompts.
    DATA mo_ui       TYPE REF TO zcl_code_popup2.
    DATA mo_messages TYPE REF TO zcl_ai_messages.
    DATA mt_history TYPE zcl_ai_messages=>tt_messages.

    " Per-question cache of idempotent tool results (read_sap_object,
    " review_sap_code). Lets a repeated identical call (the LLM sometimes
    " re-issues the same review, differing only in object-name case) be served
    " without re-running the work. Reset on each run( ); invalidated by writers.
    TYPES: BEGIN OF ty_tool_cache,
             key    TYPE string,
             result TYPE string,
           END OF ty_tool_cache.
    DATA mt_tool_cache TYPE STANDARD TABLE OF ty_tool_cache WITH NON-UNIQUE DEFAULT KEY.
    DATA mv_review_pending TYPE abap_bool.
    DATA mv_user_prompt TYPE string.
    DATA mv_log_path    TYPE string.
    " Per-session log folder (<log_path>/<date>_<time>), created once. All log
    " files for the session live here, so their names carry no date.
    DATA mv_log_dir     TYPE string.

    METHODS write_log_file
      IMPORTING
        !i_suffix  TYPE string
        !i_content TYPE string
        !i_ext     TYPE string DEFAULT 'json'
        !i_step    TYPE i      DEFAULT 0.

    " Appends one token-budget row per question to <log_dir>/_tokens.md.
    METHODS write_session_tokens.

    " Returns a corrective message when delete_sap_object is mis-used for a
    " partial deletion (a form, method, comment, line - it should be a modify),
    " otherwise empty. Acts as a deterministic guard on top of the LLM routing.
    METHODS delete_misuse_redirect
      IMPORTING
        !is_call          TYPE zcl_code_ai_api=>ty_tool_call
      RETURNING VALUE(rv_redirect) TYPE string.

    DATA mo_html_viewer    TYPE REF TO cl_gui_html_viewer.
    DATA mt_progress_steps TYPE tt_steps.
    DATA mv_total_seconds  TYPE i.
    DATA mv_total_tok_in   TYPE i.
    DATA mv_total_tok_out  TYPE i.
    DATA mv_total_tok_cached TYPE i.

    METHODS show_step
      IMPORTING
        !i_text        TYPE string OPTIONAL
        !i_agent       TYPE string OPTIONAL
        !i_prompt_type TYPE string OPTIONAL
        !i_pct         TYPE i DEFAULT 50.

    METHODS complete_last_step
      IMPORTING
        !i_is_llm  TYPE abap_bool DEFAULT abap_false
        !i_seconds TYPE i OPTIONAL
        !i_tok_in  TYPE i OPTIONAL
        !i_tok_out TYPE i OPTIONAL
        !i_tok_cached TYPE i OPTIONAL.

    METHODS render_steps_html
      RETURNING VALUE(rv_html) TYPE string.

    METHODS display_steps.

    METHODS execute_tool_call
      IMPORTING
        !is_call         TYPE zcl_code_ai_api=>ty_tool_call
      RETURNING VALUE(rv_result) TYPE string.

    METHODS confirm_and_apply
      IMPORTING
        !is_result       TYPE zif_ai_tool=>ty_result
      RETURNING VALUE(rv_message) TYPE string.

    METHODS build_system_prompt
      RETURNING VALUE(rv_prompt) TYPE string.

    " Cache key for an idempotent tool call (read_sap_object / review_sap_code),
    " case-normalised by object type+name. '' for tools that must not be cached.
    METHODS tool_cache_key
      IMPORTING
        !i_name        TYPE string
        !i_type        TYPE string
        !i_object      TYPE string
      RETURNING VALUE(rv_key) TYPE string.

    " True for tools that change object state (modify/create/delete).
    METHODS is_writer_tool
      IMPORTING
        !i_name          TYPE string
      RETURNING VALUE(rv_writer) TYPE abap_bool.

    " Shrinks the copy of a tool-results turn that is kept in mt_history and
    " re-sent on every later iteration. read_sap_object source dumps are pure
    " bloat there - review_sap_code re-reads the source itself and the
    " orchestrator only needs the object names (kept in the head) to keep
    " dispatching reviews. The FULL results were already sent once as i_prompt
    " for the immediate next call; only the resent history copy is compacted.
    METHODS compact_tool_results
      IMPORTING
        !i_text          TYPE string
      RETURNING VALUE(rv_text) TYPE string.
ENDCLASS.



CLASS zcl_ai_tool_runner IMPLEMENTATION.


  METHOD constructor.

    mo_llm      = io_llm.
    mo_context  = io_context.
    mo_prompts  = io_prompts.
    mo_ui       = io_ui.
    mv_log_path = i_log_path.
    zcl_ai_tool_factory=>initialize( io_context ).

    " Route tool sub-agent LLM calls (zcl_ai_tool_context=>ask) back through this
    " runner so they are shown, logged and counted like the orchestrator's own.
    io_context->set_host( me ).

    " Log folder layout: <log_path>/<PROVIDER>/<date>_<time>. The provider split
    " matters for separate token accounting (esp. Anthropic). Files inside drop
    " the date prefix (the folder already carries it).
    IF mv_log_path IS NOT INITIAL.
      DATA lv_base TYPE string.
      lv_base = mv_log_path.
      IF NOT ( lv_base CP '*/' OR lv_base CP '*\' ).
        lv_base = mv_log_path && '/'.
      ENDIF.

      DATA(lv_provider) = i_provider.
      TRANSLATE lv_provider TO UPPER CASE.
      IF lv_provider IS INITIAL.
        lv_provider = 'ANTHROPIC'.
      ENDIF.

      " Create the provider folder first, then the per-session folder under it.
      " rc is a mandatory CHANGING parameter of directory_create - it is filled
      " with the frontend return code; we rely on the exceptions, so it is only
      " captured to satisfy the signature (an existing folder is not an error).
      DATA lv_rc TYPE i.
      DATA(lv_prov_dir) = |{ lv_base }{ lv_provider }|.
      cl_gui_frontend_services=>directory_create(
        EXPORTING  directory = lv_prov_dir
        CHANGING   rc        = lv_rc
        EXCEPTIONS OTHERS    = 1 ).

      mv_log_dir = |{ lv_prov_dir }/{ sy-datum }_{ sy-uzeit }|.
      cl_gui_frontend_services=>directory_create(
        EXPORTING  directory = mv_log_dir
        CHANGING   rc        = lv_rc
        EXCEPTIONS OTHERS    = 1 ).
    ENDIF.

  ENDMETHOD.


  METHOD run.

    " Shortcut: single object name or search mask (word / word*) - skip LLM entirely
    DATA(lv_trimmed_prompt) = i_prompt.
    CONDENSE lv_trimmed_prompt.
    " Allow letters, digits, underscore, and trailing wildcard *
    FIND FIRST OCCURRENCE OF REGEX '[^A-Za-z0-9_*]' IN lv_trimmed_prompt.
    IF lv_trimmed_prompt IS NOT INITIAL
    AND lv_trimmed_prompt NA ' '
    AND sy-subrc <> 0.
      DATA(lv_word) = lv_trimmed_prompt.
      TRANSLATE lv_word TO UPPER CASE.

      " Detect explicit wildcard (user typed z*, zys_*)
      DATA lv_has_wildcard TYPE abap_bool.
      IF lv_word CS '*'.
        lv_has_wildcard = abap_true.
        REPLACE ALL OCCURRENCES OF '*' IN lv_word WITH ''.
        CONDENSE lv_word.
      ENDIF.

      " SAP object name heuristic: Z/Y namespace or contains underscore
      DATA lv_is_sap_name TYPE abap_bool.
      IF lv_word IS NOT INITIAL.
        DATA(lv_first) = lv_word(1).
        IF lv_word CS '_' OR lv_first = 'Z' OR lv_first = 'Y'.
          lv_is_sap_name = abap_true.
        ENDIF.
      ENDIF.

      DATA lv_direct_source TYPE string.
      " Exact lookup only when no explicit wildcard was given
      IF lv_has_wildcard = abap_false.
        lv_direct_source = zcl_ai_code_reader=>read_class( lv_word ).
        IF lv_direct_source IS INITIAL OR lv_direct_source CS 'not found'.
          CLEAR lv_direct_source.
          lv_direct_source = zcl_ai_code_reader=>read_program( lv_word ).
          IF lv_direct_source IS INITIAL OR lv_direct_source CS 'not found'.
            CLEAR lv_direct_source.
          ENDIF.
        ENDIF.
      ENDIF.

      " Wildcard search: always after an explicit *, or as fallback after exact miss
      IF lv_direct_source IS INITIAL.
        lv_direct_source = zcl_ai_code_reader=>read_program( lv_word && '*' ).
        IF lv_direct_source CS 'not found' OR lv_direct_source CS 'No objects found'.
          CLEAR lv_direct_source.
        ENDIF.
      ENDIF.

      IF lv_direct_source IS NOT INITIAL.
        rv_answer = lv_direct_source.
        mo_messages = NEW zcl_ai_messages(
          i_user_prompt = i_prompt
          io_prompts    = mo_prompts
          i_session_id  = 1 ).
        mo_messages->add_message(
          i_role        = 'user'
          i_agent       = 'read_sap_object'
          i_prompt_type = 'TOOL_CALL'
          i_content     = |read_sap_object( { lv_word } )| ).
        mo_messages->add_message(
          i_role        = 'tool'
          i_agent       = 'read_sap_object'
          i_prompt_type = 'AGENT_RESPONSE'
          i_content     = rv_answer ).
        RETURN.
      ELSEIF lv_is_sap_name = abap_true OR lv_has_wildcard = abap_true.
        " Typed a SAP name or explicit mask but nothing found - no LLM needed
        rv_answer = |Object { lv_word } not found. Check the name or add * for wildcard search.|.
        RETURN.
      ENDIF.
    ENDIF.

    DATA lt_calls   TYPE zcl_code_ai_api=>tt_tool_calls.

    DATA(lv_tools_json)    = zcl_ai_tool_factory=>build_tools_json( ).
    DATA(lv_system_prompt) = build_system_prompt( ).

    mo_messages = NEW zcl_ai_messages(
      i_user_prompt   = i_prompt
      io_prompts      = mo_prompts
      i_session_id    = 1
      i_system_prompt = lv_system_prompt ).

    DATA(lv_prompt) = i_prompt.
    CLEAR mv_review_pending.
    mv_user_prompt = i_prompt.

    " Fresh progress panel for every question
    CLEAR mt_progress_steps.
    CLEAR mv_total_seconds.
    CLEAR mv_total_tok_in.
    CLEAR mv_total_tok_out.
    CLEAR mv_total_tok_cached.

    DO c_max_iterations TIMES.

      show_step(
        i_text        = COND #( WHEN sy-index = 1
                                THEN 'Asking LLM'
                                ELSE |Asking LLM (step { sy-index })| )
        i_prompt_type = 'LLM'
        i_pct         = sy-index * 100 / c_max_iterations ).

      CLEAR lt_calls.
      DATA(lv_answer) = mo_llm->ask_with_tools(
        EXPORTING
          i_prompt        = lv_prompt
          i_system_prompt = lv_system_prompt
          it_history      = mt_history
          i_tools_json    = lv_tools_json
        IMPORTING
          et_tool_calls   = lt_calls ).

      DATA(lv_step) = sy-index.
      write_log_file( i_suffix = 'Q'   i_content = mo_llm->mv_last_raw_request  i_step = lv_step ).
      DATA lv_q_full TYPE string.
      CLEAR lv_q_full.
      lv_q_full = |[system]: { lv_system_prompt }|
               && cl_abap_char_utilities=>newline
               && '---' && cl_abap_char_utilities=>newline.
      LOOP AT mt_history INTO DATA(ls_hist_q).
        lv_q_full = lv_q_full
          && |[{ ls_hist_q-role }]: { ls_hist_q-content }|
          && cl_abap_char_utilities=>newline
          && '---' && cl_abap_char_utilities=>newline.
      ENDLOOP.
      lv_q_full = lv_q_full && |[user]: { lv_prompt }|.
      write_log_file( i_suffix = 'Q'   i_content = lv_q_full i_ext = 'txt'       i_step = lv_step ).
      write_log_file( i_suffix = 'LLM' i_content = mo_llm->mv_last_raw_response  i_step = lv_step ).
      " Extended thinking (Anthropic): log the reasoning separately when present.
      IF mo_llm->mv_last_thinking IS NOT INITIAL.
        write_log_file( i_suffix = 'THINK' i_content = mo_llm->mv_last_thinking i_ext = 'md' i_step = lv_step ).
      ENDIF.

      complete_last_step(
        i_is_llm     = abap_true
        i_seconds    = CONV #( mo_llm->get_last_seconds( ) )
        i_tok_in     = mo_llm->mv_last_tok_in
        i_tok_out    = mo_llm->mv_last_tok_out
        i_tok_cached = mo_llm->mv_last_tok_cached ).

      " Show thinking text as a progress entry right after the LLM step.
      IF mo_llm->mv_last_thinking IS NOT INITIAL.
        show_step( i_text = |Thinking: { mo_llm->mv_last_thinking }| i_prompt_type = 'LLM' ).
        complete_last_step( ).
      ENDIF.

      " Persist the user turn to the multi-turn history. The full lv_prompt was
      " just sent as i_prompt above; the history copy is compacted so big
      " read_sap_object source dumps are not re-sent on every later iteration.
      APPEND VALUE #( role = 'user' content = compact_tool_results( lv_prompt ) ) TO mt_history.

      " Always log the LLM output (text and/or requested tool calls) so the
      " History popup pairs it with the prompt: input left, output right
      DATA(lv_llm_log) = lv_answer.
      LOOP AT lt_calls INTO DATA(ls_call).
        IF lv_llm_log IS NOT INITIAL.
          lv_llm_log = lv_llm_log && cl_abap_char_utilities=>newline.
        ENDIF.
        lv_llm_log = lv_llm_log
          && |TOOL CALL: { ls_call-name }( { ls_call-arguments } )|.
      ENDLOOP.
      " Write LLM.md after lv_llm_log is built (includes tool calls when answer is empty)
      write_log_file( i_suffix = 'LLM' i_content = lv_llm_log i_ext = 'md' i_step = lv_step ).
      mo_messages->add_message(
        i_role             = 'assistant'
        i_agent            = 'TOOL_RUNNER'
        i_prompt_type      = COND #( WHEN lt_calls IS INITIAL
                                     THEN 'FINAL_ANSWER'
                                     ELSE 'LLM_RESPONSE' )
        i_duration_seconds = mo_llm->get_last_seconds( )
        i_tok_in           = mo_llm->mv_last_tok_in
        i_tok_out          = mo_llm->mv_last_tok_out
        i_tok_cached       = mo_llm->mv_last_tok_cached
        i_content          = lv_llm_log ).

      " No tool calls -> this is the final user-facing answer
      IF lt_calls IS INITIAL.
        rv_answer = lv_answer.
        " Dedicated answer log so the final reply is easy to find without
        " hunting for the last *_LLM.md among all the step logs.
        write_log_file( i_suffix = 'A' i_content = lv_answer i_ext = 'md' i_step = lv_step ).
        APPEND VALUE #( role = 'assistant' content = lv_answer ) TO mt_history.
        write_session_tokens( ).
        RETURN.
      ENDIF.

      IF lv_answer IS NOT INITIAL.
        APPEND VALUE #( role = 'assistant' content = lv_answer ) TO mt_history.
      ENDIF.

      " Execute each tool; log the call (input) and its result (output) as a
      " pair so the History popup shows them side by side
      DATA lv_results TYPE string.
      CLEAR lv_results.
      LOOP AT lt_calls INTO ls_call.
        mo_messages->add_message(
          i_role        = 'user'
          i_agent       = ls_call-name
          i_prompt_type = 'TOOL_CALL'
          i_content     = |{ ls_call-name }( { ls_call-arguments } )| ).
        " Show target object (type + name from JSON arguments) in the step label
        DATA lv_step_type TYPE string.
        DATA lv_step_name TYPE string.
        CLEAR: lv_step_type, lv_step_name.
        FIND FIRST OCCURRENCE OF REGEX '"object_type"\s*:\s*"([^"]*)"'
          IN ls_call-arguments SUBMATCHES lv_step_type.
        FIND FIRST OCCURRENCE OF REGEX '"object_name"\s*:\s*"([^"]*)"'
          IN ls_call-arguments SUBMATCHES lv_step_name.
        DATA(lv_step_object) = |{ lv_step_type } { lv_step_name }|.
        CONDENSE lv_step_object.
        show_step( i_text = COND #(
          WHEN lv_step_object IS NOT INITIAL
          THEN |Tool { ls_call-name } { lv_step_object }...|
          ELSE |Tool { ls_call-name }...| ) ).
        DATA(lv_result) = execute_tool_call( ls_call ).
        complete_last_step( ).
        write_log_file( i_suffix  = 'TOOL'
                        i_content = |{ ls_call-name }({ ls_call-arguments })| &&
                                    cl_abap_char_utilities=>newline &&
                                    lv_result
                        i_step    = lv_step ).
        mo_messages->add_message(
          i_role        = 'tool'
          i_agent       = ls_call-name
          i_prompt_type = 'AGENT_RESPONSE'
          i_content     = lv_result ).

        " Tool error - show it directly, do not feed back to LLM
        IF lv_result CP 'Error:*'.
          rv_answer = |Tool { ls_call-name }: { lv_result }|.
          write_session_tokens( ).
          RETURN.
        ENDIF.

        lv_results = lv_results
          && |TOOL RESULT [{ ls_call-name }]:|
          && cl_abap_char_utilities=>newline
          && lv_result
          && cl_abap_char_utilities=>newline.
      ENDLOOP.

      " A tool launched an interactive diff review - stop the agentic loop so the
      " final LLM answer does not overwrite the diff in the answer panel. The save
      " is driven by the diff toolbar (approve/decline) from here on.
      IF mv_review_pending = abap_true.
        rv_answer = lv_results.
        write_session_tokens( ).
        RETURN.
      ENDIF.

      lv_prompt = lv_results
        && cl_abap_char_utilities=>newline
        && mo_context->read_agent_file( 'tool_continue.md' ).
      mo_messages->add_message(
        i_role        = 'user'
        i_agent       = 'TOOL_RUNNER'
        i_prompt_type = 'LLM_INPUT'
        i_content     = lv_prompt ).

    ENDDO.

    rv_answer = |Error: tool loop did not finish within { c_max_iterations } iterations.|.
    write_session_tokens( ).

  ENDMETHOD.


  METHOD execute_tool_call.

    DATA(lo_tool) = zcl_ai_tool_factory=>get_tool( is_call-name ).
    IF lo_tool IS INITIAL.
      rv_result = |Error: unknown tool '{ is_call-name }'|.
      RETURN.
    ENDIF.

    " Deterministic guard: block whole-object deletion when the request is really
    " about removing a PART of the code, and steer the LLM to modify_sap_object.
    DATA(lv_redirect) = delete_misuse_redirect( is_call ).
    IF lv_redirect IS NOT INITIAL.
      rv_result = lv_redirect.
      RETURN.
    ENDIF.

    DATA(ls_result) = lo_tool->execute( i_arguments = is_call-arguments ).

    IF ls_result-error_text IS NOT INITIAL.
      rv_result = |Error: { ls_result-error_text }|.
      RETURN.
    ENDIF.

    rv_result = ls_result-xml_payload.

    " Destructive actions stay in ONE place: confirmation + save/delete here,
    " never inside the tools themselves
    IF ls_result-save_required = abap_true.
      DATA(lv_apply_msg) = confirm_and_apply( ls_result ).
      rv_result = rv_result
        && cl_abap_char_utilities=>newline
        && |APPLY RESULT: { lv_apply_msg }|.
    ENDIF.

  ENDMETHOD.


  METHOD delete_misuse_redirect.

    " Only guards delete_sap_object calls.
    IF is_call-name <> 'delete_sap_object'.
      RETURN.
    ENDIF.

    " Look for part-of-code indicators in the original user request. If present,
    " the user wants to remove something INSIDE the object, not the whole object.
    DATA(lv_p) = mv_user_prompt.
    TRANSLATE lv_p TO UPPER CASE.

    DATA lt_kw TYPE STANDARD TABLE OF string WITH NON-UNIQUE DEFAULT KEY.
    " English
    APPEND 'FORM' TO lt_kw.       APPEND 'SUBROUTINE' TO lt_kw.
    APPEND 'PERFORM' TO lt_kw.    APPEND 'METHOD' TO lt_kw.
    APPEND 'COMMENT' TO lt_kw.    APPEND 'LINE' TO lt_kw.
    APPEND 'VARIABLE' TO lt_kw.   APPEND 'FIELD' TO lt_kw.
    APPEND 'BLOCK' TO lt_kw.      APPEND 'PARAMETER' TO lt_kw.
    APPEND 'HEADER' TO lt_kw.
    " Russian / Ukrainian
    APPEND 'ФОРМ' TO lt_kw.       APPEND 'МЕТОД' TO lt_kw.
    APPEND 'КОММЕНТ' TO lt_kw.    APPEND 'КОМЕНТ' TO lt_kw.
    APPEND 'СТРОК' TO lt_kw.      APPEND 'РЯДОК' TO lt_kw.
    APPEND 'РЯДК' TO lt_kw.       APPEND 'ПЕРЕМЕНН' TO lt_kw.
    APPEND 'ЗМІНН' TO lt_kw.      APPEND 'ПОЛЕ' TO lt_kw.
    APPEND 'БЛОК' TO lt_kw.       APPEND 'ШАПК' TO lt_kw.
    APPEND 'ПІДПРОГРАМ' TO lt_kw. APPEND 'ПОДПРОГРАМ' TO lt_kw.

    DATA(lv_is_part) = abap_false.
    LOOP AT lt_kw INTO DATA(lv_kw).
      IF lv_p CS lv_kw.
        lv_is_part = abap_true.
        EXIT.
      ENDIF.
    ENDLOOP.

    IF lv_is_part = abap_false.
      RETURN.
    ENDIF.

    DATA lv_type TYPE string.
    DATA lv_name TYPE string.
    FIND FIRST OCCURRENCE OF REGEX '"object_type"\s*:\s*"([^"]*)"'
      IN is_call-arguments SUBMATCHES lv_type.
    FIND FIRST OCCURRENCE OF REGEX '"object_name"\s*:\s*"([^"]*)"'
      IN is_call-arguments SUBMATCHES lv_name.

    rv_redirect = mo_context->read_agent_file( 'delete_misuse_redirect.md' ).
    REPLACE ALL OCCURRENCES OF '{TYPE}' IN rv_redirect WITH lv_type.
    REPLACE ALL OCCURRENCES OF '{NAME}' IN rv_redirect WITH lv_name.

  ENDMETHOD.


  METHOD confirm_and_apply.

    " A diff review is already open from an earlier tool call in this same run -
    " never save blindly or open a second popup on top of it.
    IF mv_review_pending = abap_true.
      rv_message = 'A code review is already open - approve/decline it first.'.
      RETURN.
    ENDIF.

    DATA(lv_is_delete) = boolc( is_result-xml_payload CS '<code_deleted' ).

    " Proposed source for the diff. Normally the tool fills final_source; if it
    " did not (e.g. only the raw envelope is available), recover the code from
    " the xml_payload so a code review is still shown instead of a blind popup.
    DATA(lv_new_code) = is_result-final_source.
    IF lv_new_code IS INITIAL AND lv_is_delete = abap_false.
      lv_new_code = is_result-xml_payload.
      REPLACE FIRST OCCURRENCE OF REGEX '<code_modified[^>]*>' IN lv_new_code WITH ''.
      REPLACE FIRST OCCURRENCE OF '</code_modified>' IN lv_new_code WITH ''.
      REPLACE FIRST OCCURRENCE OF REGEX '<change_summary>[^<]*</change_summary>' IN lv_new_code WITH ''.
      " Remove the (multi-line) <metadata> block. ABAP classic regex has no
      " newline-spanning class (\S/\s fail), so cut the section out manually.
      DATA lv_m1  TYPE i.
      DATA lv_m2  TYPE i.
      DATA lv_mln TYPE i.
      FIND FIRST OCCURRENCE OF '<metadata>' IN lv_new_code MATCH OFFSET lv_m1.
      IF sy-subrc = 0.
        FIND FIRST OCCURRENCE OF '</metadata>' IN lv_new_code MATCH OFFSET lv_m2.
        IF sy-subrc = 0.
          lv_mln = lv_m2 + strlen( '</metadata>' ) - lv_m1.
          REPLACE SECTION OFFSET lv_m1 LENGTH lv_mln OF lv_new_code WITH ''.
        ENDIF.
      ENDIF.
      REPLACE ALL OCCURRENCES OF REGEX '</?full_source>' IN lv_new_code WITH ''.
      CONDENSE lv_new_code.
    ENDIF.

    " Decide via SEPARATE checks (not one compound AND) whether the diff review
    " can be shown. A single combined condition proved unreliable here, so each
    " precondition flips the flag on its own.
    DATA lv_can_diff TYPE abap_bool VALUE abap_true.
    IF lv_is_delete = abap_true.
      lv_can_diff = abap_false.
    ENDIF.
    IF lv_new_code IS INITIAL.
      lv_can_diff = abap_false.
    ENDIF.
    IF mo_ui IS NOT BOUND.
      lv_can_diff = abap_false.
    ENDIF.

    IF lv_can_diff = abap_false.
      DATA(lv_f_delete) = COND string( WHEN lv_is_delete = abap_true THEN 'YES' ELSE 'no' ).
      DATA(lv_f_code)   = COND string( WHEN lv_new_code IS NOT INITIAL THEN |YES(len={ strlen( lv_new_code ) })| ELSE 'NO(empty)' ).
      DATA(lv_f_ui)     = COND string( WHEN mo_ui IS BOUND THEN 'YES' ELSE 'NO' ).
      MESSAGE |DIFF SKIPPED { is_result-object_type } { is_result-object_name }: | &&
              |is_delete={ lv_f_delete }, has_code={ lv_f_code }, ui_bound={ lv_f_ui }| TYPE 'I'.
    ENDIF.

    " Diff review is mandatory for every save when UI is available. When the
    " tool did not supply the original source (e.g. create_sap_object on an
    " existing object), read the current version so the user still sees a diff;
    " for a truly new object the diff is shown against empty code.
    IF lv_can_diff = abap_true.
      DATA(lv_old_code) = is_result-original_source.
      IF lv_old_code IS INITIAL.
        CASE is_result-object_type.
          WHEN 'CLAS' OR 'METH'.
            lv_old_code = zcl_ai_code_reader=>read_class( is_result-object_name ).
          WHEN OTHERS.
            lv_old_code = zcl_ai_code_reader=>read_program(
              i_program     = is_result-object_name
              i_object_type = is_result-object_type ).
        ENDCASE.
        IF lv_old_code CS 'not found' OR lv_old_code CS 'cannot be read'.
          CLEAR lv_old_code.
        ENDIF.
      ENDIF.
      mv_review_pending = abap_true.
      MESSAGE |DIFF OPENED -> { is_result-object_type } { is_result-object_name }, | &&
              |old_len={ strlen( lv_old_code ) }, new_len={ strlen( lv_new_code ) }| TYPE 'I'.
      rv_message = mo_ui->review_and_save(
        i_old_code    = lv_old_code
        i_new_code    = lv_new_code
        i_object_type = is_result-object_type
        i_object_name = is_result-object_name ).
      RETURN.
    ENDIF.

    " Fallback: simple confirm popup (delete or no UI)
    DATA lv_answer TYPE c LENGTH 1.
    DATA(lv_question) = COND string(
      WHEN lv_is_delete = abap_true
      THEN |Delete { is_result-object_type } { is_result-object_name }?|
      ELSE |Save changes to { is_result-object_type } { is_result-object_name }?| ).

    CALL FUNCTION 'POPUP_TO_CONFIRM'
      EXPORTING
        titlebar              = 'AI Tool Runner'
        text_question         = lv_question
        text_button_1         = 'Yes'
        text_button_2         = 'No'
        default_button        = '2'
        display_cancel_button = ' '
      IMPORTING
        answer                = lv_answer
      EXCEPTIONS
        OTHERS                = 1.

    IF sy-subrc <> 0 OR lv_answer <> '1'.
      rv_message = 'Rejected by user - nothing was changed.'.
      RETURN.
    ENDIF.

    " Invoke the write capability purely by dynamic name so the runner
    " (read-only base) carries NO compile-time dependency on the saver and core
    " needs NO interface. When the saver class is not installed (read-only
    " delivery, e.g. the OTR translator client), the dynamic call raises
    " cx_sy_dyn_call_error and the agent reports it instead of mutating anything.
    TRY.
        IF lv_is_delete = abap_true.
          CALL METHOD ('ZCL_CODE_OBJECT_SAVER')=>delete
            EXPORTING
              i_object_type = is_result-object_type
              i_object_name = is_result-object_name
            RECEIVING
              rv_message    = rv_message.
        ELSE.
          IF lv_new_code IS INITIAL.
            rv_message = 'Error: no final source to save.'.
            RETURN.
          ENDIF.
          CALL METHOD ('ZCL_CODE_OBJECT_SAVER')=>save
            EXPORTING
              i_object_type = is_result-object_type
              i_object_name = is_result-object_name
              i_source      = lv_new_code
            RECEIVING
              rv_message    = rv_message.
        ENDIF.
      CATCH cx_sy_dyn_call_error.
        rv_message = 'Write capability is not installed (read-only platform) - '
                  && 'nothing was changed. To enable create/modify/delete, install '
                  && 'https://github.com/ysichov/ABAP-AI-CODE-TOOLS'.
        RETURN.
    ENDTRY.

  ENDMETHOD.


  METHOD build_system_prompt.

    " Static base: role / guardrails only. Tool-specific capabilities must NOT
    " be hardcoded here - they are appended below from the registry so the prompt
    " advertises exactly the tools that are actually installed (single source of
    " truth shared with build_tools_json).
    rv_prompt = mo_context->read_agent_file( 'tool_runner.md' ).

    DATA(lv_tools) = zcl_ai_tool_factory=>build_tools_prompt( ).
    IF lv_tools IS NOT INITIAL.
      rv_prompt = rv_prompt
               && cl_abap_char_utilities=>newline
               && cl_abap_char_utilities=>newline
               && |## Available tools|
               && cl_abap_char_utilities=>newline
               && cl_abap_char_utilities=>newline
               && lv_tools.
    ENDIF.

    " Read-only guidance. Phrased conditionally so it is correct whether or not
    " the write add-on is installed: the model only acts on it when it has no
    " create/modify/delete tool available. Keeps the install hint in one place
    " without the base depending on the tool classes.
    rv_prompt = rv_prompt
             && cl_abap_char_utilities=>newline
             && cl_abap_char_utilities=>newline
             && |## Code modification capability| && cl_abap_char_utilities=>newline
             && |Creating, modifying or deleting ABAP objects requires the optional | &&
                |ABAP-AI-CODE-TOOLS add-on. If you do NOT have a create/modify/delete | &&
                |tool available in this session, do not attempt or simulate the change - | &&
                |tell the user it requires installing | &&
                |https://github.com/ysichov/ABAP-AI-CODE-TOOLS|.

  ENDMETHOD.


  METHOD agent_ask.

    " Show the sub-call as its own progress step BEFORE the blocking HTTP call,
    " so the panel reflects what is happening instead of looking frozen.
    show_step(
      i_text        = COND #( WHEN i_label IS NOT INITIAL
                              THEN |Asking AI: { i_label }|
                              ELSE |Asking AI (sub-agent)| )
      i_prompt_type = 'LLM' ).

    rv_answer = mo_llm->ask(
      i_prompt        = i_prompt
      i_system_prompt = i_system_prompt ).

    " Log the sub-call like an orchestrator step (raw request / response), so the
    " whole "inner kitchen" is on disk too, not only on screen.
    DATA(lv_step) = lines( mt_progress_steps ).
    write_log_file( i_suffix = 'SUBQ'   i_content = mo_llm->mv_last_raw_request  i_step = lv_step ).
    write_log_file( i_suffix = 'SUBLLM' i_content = mo_llm->mv_last_raw_response i_step = lv_step ).

    " Complete the step with the sub-call's real numbers and fold them into Total.
    complete_last_step(
      i_is_llm     = abap_true
      i_seconds    = CONV #( mo_llm->get_last_seconds( ) )
      i_tok_in     = mo_llm->mv_last_tok_in
      i_tok_out    = mo_llm->mv_last_tok_out
      i_tok_cached = mo_llm->mv_last_tok_cached ).

  ENDMETHOD.


  METHOD tool_cache_key.

    DATA(lv_name) = i_name.
    TRANSLATE lv_name TO UPPER CASE.

    " Only idempotent, object-scoped reads are safe to cache.
    CASE lv_name.
      WHEN 'READ_SAP_OBJECT' OR 'REVIEW_SAP_CODE'.
        DATA(lv_type) = i_type.
        DATA(lv_obj)  = i_object.
        TRANSLATE lv_type TO UPPER CASE.
        TRANSLATE lv_obj  TO UPPER CASE.
        CONDENSE lv_type.
        CONDENSE lv_obj.
        IF lv_obj IS NOT INITIAL.
          rv_key = |{ lv_name }|{ lv_type }|{ lv_obj }|.
        ENDIF.
    ENDCASE.

  ENDMETHOD.


  METHOD is_writer_tool.

    DATA(lv_name) = i_name.
    TRANSLATE lv_name TO UPPER CASE.
    rv_writer = xsdbool( lv_name = 'MODIFY_SAP_OBJECT'
                      OR lv_name = 'CREATE_SAP_OBJECT'
                      OR lv_name = 'DELETE_SAP_OBJECT' ).

  ENDMETHOD.


  METHOD compact_tool_results.

    rv_text = i_text.
    " Cheap guard: small turns (e.g. the plain user question) need no work.
    IF strlen( rv_text ) <= 4000.
      RETURN.
    ENDIF.

    DATA lt_lines TYPE STANDARD TABLE OF string WITH NON-UNIQUE DEFAULT KEY.
    SPLIT rv_text AT cl_abap_char_utilities=>newline INTO TABLE lt_lines.

    DATA lv_out     TYPE string.
    DATA lv_in_read TYPE abap_bool.   " currently inside a read_sap_object block
    DATA lv_kept    TYPE i.           " head lines already kept from the block
    DATA lv_dropped TYPE i.           " source lines dropped from the block
    CONSTANTS c_head TYPE i VALUE 6.  " head lines kept (object headers / names)

    LOOP AT lt_lines INTO DATA(lv_line).
      " A TOOL RESULT marker closes any open read block and opens a new one.
      IF lv_line CS 'TOOL RESULT ['.
        IF lv_in_read = abap_true AND lv_dropped > 0.
          lv_out = lv_out && |... [{ lv_dropped } source line(s) omitted from history]|
                          && cl_abap_char_utilities=>newline.
        ENDIF.
        lv_in_read = xsdbool( lv_line CS 'TOOL RESULT [read_sap_object]' ).
        CLEAR: lv_kept, lv_dropped.
        lv_out = lv_out && lv_line && cl_abap_char_utilities=>newline.
        CONTINUE.
      ENDIF.

      IF lv_in_read = abap_true.
        IF lv_kept < c_head.
          lv_kept = lv_kept + 1.
          lv_out = lv_out && lv_line && cl_abap_char_utilities=>newline.
        ELSE.
          lv_dropped = lv_dropped + 1.
        ENDIF.
      ELSE.
        lv_out = lv_out && lv_line && cl_abap_char_utilities=>newline.
      ENDIF.
    ENDLOOP.

    " Flush a trailing note if the text ended while still inside a read block.
    IF lv_in_read = abap_true AND lv_dropped > 0.
      lv_out = lv_out && |... [{ lv_dropped } source line(s) omitted from history]|
                      && cl_abap_char_utilities=>newline.
    ENDIF.

    rv_text = lv_out.

  ENDMETHOD.


  METHOD get_messages.

    ro_messages = mo_messages.

  ENDMETHOD.


  METHOD clear_session.

    CLEAR mt_history.
    CLEAR mo_messages.

  ENDMETHOD.


  METHOD is_review_pending.

    rv_pending = mv_review_pending.

  ENDMETHOD.


  METHOD set_html_viewer.

    mo_html_viewer = io_viewer.
    CLEAR mt_progress_steps.
    CLEAR mv_total_seconds.
    CLEAR mv_total_tok_in.
    CLEAR mv_total_tok_out.
    CLEAR mv_total_tok_cached.

  ENDMETHOD.


  METHOD show_step.

    CALL FUNCTION 'SAPGUI_PROGRESS_INDICATOR'
      EXPORTING percentage = i_pct text = i_text.

    CHECK mo_html_viewer IS BOUND.

    " Mark previous last step as done
    DATA(lv_last) = lines( mt_progress_steps ).
    IF lv_last > 0.
      FIELD-SYMBOLS <ls_prev> TYPE ty_step.
      READ TABLE mt_progress_steps ASSIGNING <ls_prev> INDEX lv_last.
      IF sy-subrc = 0.
        <ls_prev>-done = abap_true.
      ENDIF.
    ENDIF.

    APPEND VALUE ty_step(
      text        = i_text
      agent       = i_agent
      prompt_type = i_prompt_type
      done        = abap_false ) TO mt_progress_steps.

    display_steps( ).

  ENDMETHOD.


  METHOD complete_last_step.

    CHECK mo_html_viewer IS BOUND.

    DATA(lv_last) = lines( mt_progress_steps ).
    CHECK lv_last > 0.

    FIELD-SYMBOLS <ls_step> TYPE ty_step.
    READ TABLE mt_progress_steps ASSIGNING <ls_step> INDEX lv_last.
    CHECK sy-subrc = 0.

    " A sub-agent call (agent_ask) already completed this step with its own
    " seconds/tokens. The post-execute complete_last_step( ) from the tool loop
    " must not overwrite that with zeros.
    IF <ls_step>-done = abap_true.
      RETURN.
    ENDIF.

    <ls_step>-done       = abap_true.
    <ls_step>-is_llm     = i_is_llm.
    <ls_step>-seconds    = i_seconds.
    <ls_step>-tok_in     = i_tok_in.
    <ls_step>-tok_out    = i_tok_out.
    <ls_step>-tok_cached = i_tok_cached.

    IF i_is_llm = abap_true.
      mv_total_seconds    = mv_total_seconds    + i_seconds.
      mv_total_tok_in     = mv_total_tok_in     + i_tok_in.
      mv_total_tok_out    = mv_total_tok_out    + i_tok_out.
      mv_total_tok_cached = mv_total_tok_cached + i_tok_cached.
    ENDIF.

    display_steps( ).

  ENDMETHOD.


  METHOD display_steps.

    DATA(lv_html) = render_steps_html( ).
    DATA lt_html TYPE STANDARD TABLE OF w3html WITH NON-UNIQUE DEFAULT KEY.
    DATA lv_off TYPE i.
    WHILE lv_off < strlen( lv_html ).
      DATA(lv_chunk) = nmin( val1 = 255 val2 = strlen( lv_html ) - lv_off ).
      APPEND VALUE w3html( line = substring( val = lv_html off = lv_off len = lv_chunk ) )
        TO lt_html.
      lv_off = lv_off + lv_chunk.
    ENDWHILE.
    DATA lv_url TYPE c LENGTH 255.
    mo_html_viewer->load_data(
      EXPORTING type = 'text' subtype = 'html'
      IMPORTING assigned_url = lv_url
      CHANGING  data_table   = lt_html
      EXCEPTIONS OTHERS = 1 ).
    CHECK sy-subrc = 0.
    mo_html_viewer->show_url( EXPORTING url = lv_url EXCEPTIONS OTHERS = 1 ).
    cl_gui_cfw=>flush( ).

  ENDMETHOD.


  METHOD render_steps_html.

    DATA lv_rows TYPE string.
    LOOP AT mt_progress_steps INTO DATA(ls_step).
      DATA(lv_label) = COND string(
        WHEN ls_step-agent IS NOT INITIAL THEN |Agent { ls_step-agent }|
        WHEN ls_step-text  IS NOT INITIAL THEN ls_step-text
        WHEN ls_step-prompt_type IS NOT INITIAL THEN ls_step-prompt_type ).
      REPLACE ALL OCCURRENCES OF '&' IN lv_label WITH '&amp;'.
      REPLACE ALL OCCURRENCES OF '<' IN lv_label WITH '&lt;'.
      REPLACE ALL OCCURRENCES OF '>' IN lv_label WITH '&gt;'.

      DATA(lv_is_llm) = xsdbool( ls_step-prompt_type = 'LLM' OR ls_step-is_llm = abap_true ).

      IF ls_step-done = abap_true.
        DATA(lv_info) = VALUE string( ).
        IF lv_is_llm = abap_true.
          lv_info = |<span class="info">{ ls_step-seconds }s|.
          IF ls_step-tok_in > 0.
            lv_info = lv_info && | Tokens: inp:{ ls_step-tok_in }, out:{ ls_step-tok_out }|.
            IF ls_step-tok_cached > 0.
              lv_info = lv_info && |, cached:{ ls_step-tok_cached }|.
            ENDIF.
          ENDIF.
          lv_info = lv_info && |</span>|.
          lv_rows = lv_rows
            && |<div class="step done">&#x2713; { lv_label }: { lv_info }</div>|.
        ELSE.
          lv_rows = lv_rows
            && |<div class="step done">&#x2713; { lv_label }</div>|.
        ENDIF.
      ELSE.
        IF lv_is_llm = abap_true.
          lv_rows = lv_rows
            && |<div class="step active">&#x23F3; { lv_label } is working...</div>|.
        ELSE.
          lv_rows = lv_rows
            && |<div class="step active">&#x23F3; { lv_label }</div>|.
        ENDIF.
      ENDIF.
    ENDLOOP.

    IF mv_total_seconds > 0.
      lv_rows = lv_rows
        && |<div class="total">Total: { mv_total_seconds }s|.
      IF mv_total_tok_in > 0.
        lv_rows = lv_rows && | Tokens: inp:{ mv_total_tok_in }, out:{ mv_total_tok_out }|.
        IF mv_total_tok_cached > 0.
          lv_rows = lv_rows && |, cached:{ mv_total_tok_cached }|.
        ENDIF.
      ENDIF.
      lv_rows = lv_rows && |</div>|.
    ENDIF.

    rv_html =
      |<!DOCTYPE html><html><head><meta charset="utf-8"><style>|
      && |body\{font-family:Segoe UI,Arial,sans-serif;margin:12px;background:#f5f5f5\}|
      && |.step\{padding:5px 10px;margin:3px 0;border-radius:3px;font-size:13px\}|
      && |.done\{color:#2e7d32\}|
      && |.active\{color:#0033aa;font-style:italic\}|
      && |.info\{color:#888;font-size:11px\}|
      && |.total\{margin-top:8px;padding:5px 10px;font-size:12px;border-radius:3px;|
      && |color:#0033aa;font-weight:bold\}|
      && |</style></head><body>|
      && lv_rows
      && |</body></html>|.

  ENDMETHOD.


  METHOD write_log_file.
    " Write i_content to <log_dir>/<time>_<session><step>_<suffix>.<ext> on the
    " presentation server via GUI_DOWNLOAD (UTF-8). The date lives in the folder
    " name (mv_log_dir), so it is not repeated in the file name.
    IF mv_log_dir IS INITIAL OR i_content IS INITIAL.
      RETURN.
    ENDIF.

    DATA lv_time TYPE string.
    DATA(lv_h)  = sy-uzeit(2).
    DATA(lv_m)  = sy-uzeit+2(2).
    DATA(lv_s)  = sy-uzeit+4(2).
    lv_time = |{ lv_h }{ lv_m }{ lv_s }|.

    DATA lv_step_part TYPE string.
    IF i_step > 0.
      lv_step_part = |_{ i_step }|.
    ENDIF.
    DATA(lv_filename) = |{ mv_log_dir }/{ lv_time }_{ mv_session_num }{ lv_step_part }_{ i_suffix }.{ i_ext }|.

    DATA lt_data TYPE TABLE OF string.
    DATA(lv_norm) = i_content.
    REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>cr_lf IN lv_norm
      WITH cl_abap_char_utilities=>newline.
    SPLIT lv_norm AT cl_abap_char_utilities=>newline INTO TABLE lt_data.

    cl_gui_frontend_services=>gui_download(
      EXPORTING
        filename             = lv_filename
        filetype             = 'ASC'
        codepage             = '4110'
        confirm_overwrite    = ' '
        show_transfer_status = ' '
      CHANGING
        data_tab             = lt_data
      EXCEPTIONS
        OTHERS               = 1 ).

  ENDMETHOD.


  METHOD write_session_tokens.
    " One running token-budget file per session. Each finished question appends
    " a row with its totals (the date is in the folder name).
    IF mv_log_dir IS INITIAL.
      RETURN.
    ENDIF.

    DATA(lv_total) = mv_total_tok_in + mv_total_tok_out.
    DATA(lv_time)  = |{ sy-uzeit(2) }:{ sy-uzeit+2(2) }:{ sy-uzeit+4(2) }|.

    " Keep the question short and on one line for the row.
    DATA(lv_q) = mv_user_prompt.
    REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>cr_lf  IN lv_q WITH ' '.
    REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>newline IN lv_q WITH ' '.
    IF strlen( lv_q ) > 60.
      lv_q = lv_q(60).
    ENDIF.

    DATA lt_row TYPE TABLE OF string.
    APPEND |{ lv_time } | &&
           |in:{ mv_total_tok_in } out:{ mv_total_tok_out } | &&
           |cached:{ mv_total_tok_cached } total:{ lv_total } | &&
           |{ mv_total_seconds }s | &&
           |{ lv_q }| TO lt_row.

    cl_gui_frontend_services=>gui_download(
      EXPORTING
        filename             = |{ mv_log_dir }/_tokens.md|
        filetype             = 'ASC'
        codepage             = '4110'
        append               = 'X'
        confirm_overwrite    = ' '
        show_transfer_status = ' '
      CHANGING
        data_tab             = lt_row
      EXCEPTIONS
        OTHERS               = 1 ).

  ENDMETHOD.
ENDCLASS.
