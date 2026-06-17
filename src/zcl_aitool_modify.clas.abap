CLASS zcl_aitool_modify DEFINITION
  PUBLIC
  INHERITING FROM zcl_aitool_base
  CREATE PUBLIC.

  PUBLIC SECTION.
    CONSTANTS c_tool_name TYPE string VALUE 'modify_sap_object'.

    METHODS zif_ai_tool~get_tool_name REDEFINITION.
    METHODS zif_ai_tool~execute       REDEFINITION.

  PROTECTED SECTION.
  PRIVATE SECTION.
    " Pipeline steps - execute( ) is just the conductor
    METHODS read_current_source
      IMPORTING
        !i_type          TYPE string
        !i_name          TYPE string
      RETURNING VALUE(rv_source) TYPE string.

    METHODS call_llm_processor
      IMPORTING
        !i_source        TYPE string
        !i_action        TYPE string
      RETURNING VALUE(rv_answer) TYPE string.

    METHODS extract_envelope_code
      IMPORTING
        !i_answer        TYPE string
      RETURNING VALUE(rv_code) TYPE string.

    METHODS merge_with_current
      IMPORTING
        !i_type          TYPE string
        !i_full_source   TYPE string
        !i_changed_parts TYPE string
      RETURNING VALUE(rv_merged) TYPE string.
ENDCLASS.



CLASS zcl_aitool_modify IMPLEMENTATION.


  METHOD zif_ai_tool~get_tool_name.

    rv_name = c_tool_name.

  ENDMETHOD.


  METHOD zif_ai_tool~execute.

    DATA(lv_type)   = get_json_attribute( i_json = i_arguments i_name = 'object_type' ).
    DATA(lv_name)   = get_json_attribute( i_json = i_arguments i_name = 'object_name' ).
    DATA(lv_action) = get_json_attribute( i_json = i_arguments i_name = 'action_description' ).
    TRANSLATE lv_type TO UPPER CASE.
    TRANSLATE lv_name TO UPPER CASE.
    CONDENSE lv_type.
    CONDENSE lv_name.

    IF lv_name IS INITIAL OR lv_action IS INITIAL.
      rs_result-error_text = 'modify_sap_object: object_name or action_description is empty'.
      RETURN.
    ENDIF.

    " 1. READ - current source comes via i_context or is read now
    DATA(lv_source) = i_context.
    IF lv_source IS INITIAL.
      lv_source = read_current_source( i_type = lv_type i_name = lv_name ).
    ENDIF.
    IF lv_source IS INITIAL.
      rs_result-error_text = |modify_sap_object: { lv_type } { lv_name } not found|.
      RETURN.
    ENDIF.

    " 2. LLM produces the <code_modified> envelope with changed parts only
    DATA(lv_answer) = call_llm_processor(
      i_source = lv_source
      i_action = lv_action ).
    IF lv_answer NS '<code_modified'.
      rs_result-error_text = 'modify_sap_object: LLM returned no <code_modified> envelope'.
      rs_result-xml_payload = lv_answer.
      RETURN.
    ENDIF.

    " 3. Merge changed parts into the full current source
    DATA(lv_changed) = extract_envelope_code( lv_answer ).
    DATA(lv_merged) = merge_with_current(
      i_type          = lv_type
      i_full_source   = lv_source
      i_changed_parts = lv_changed ).

    " 4. Hand over to the runner: diff review + confirmation + save are its job
    rs_result-xml_payload      = lv_answer.
    rs_result-save_required    = abap_true.
    rs_result-object_type      = lv_type.
    rs_result-object_name      = lv_name.
    rs_result-original_source  = lv_source.
    rs_result-final_source     = lv_merged.

  ENDMETHOD.


  METHOD read_current_source.

    CASE i_type.
      WHEN 'CLAS' OR 'METH'.
        " Signature changes need the whole class anyway
        DATA(lv_class) = i_name.
        IF lv_class CS '=>'.
          SPLIT lv_class AT '=>' INTO lv_class DATA(lv_dummy).
        ENDIF.
        rv_source = zcl_ai_code_reader=>read_class( lv_class ).
      WHEN OTHERS.
        rv_source = zcl_ai_code_reader=>read_program(
          i_program     = i_name
          i_object_type = i_type ).
    ENDCASE.

  ENDMETHOD.


  METHOD call_llm_processor.

    DATA(lv_system_prompt) = mo_context->read_agent_file( c_tool_name && '.md' ).

    DATA(lv_prompt) = mo_context->read_agent_file( 'modify_user_template.md' ).
    REPLACE FIRST OCCURRENCE OF '{ACTION}' IN lv_prompt WITH i_action.
    lv_prompt = lv_prompt && cl_abap_char_utilities=>newline && i_source.

    rv_answer = mo_context->mo_llm->ask(
      i_prompt        = lv_prompt
      i_system_prompt = lv_system_prompt ).

  ENDMETHOD.


  METHOD extract_envelope_code.

    " Strip the outer envelope and metadata; keep the inner code blocks
    " (sections / methods / full_source) for the merge step
    rv_code = i_answer.
    REPLACE FIRST OCCURRENCE OF REGEX '<code_modified[^>]*>' IN rv_code WITH ''.
    REPLACE FIRST OCCURRENCE OF '</code_modified>' IN rv_code WITH ''.
    REPLACE FIRST OCCURRENCE OF REGEX '<change_summary>[^<]*</change_summary>' IN rv_code WITH ''.
    " Remove the (multi-line) <metadata> block. ABAP classic regex has no
    " newline-spanning character class, so cut the section out manually instead
    " of '<metadata>.*</metadata>' (which would only match on a single line).
    DATA lv_m1  TYPE i.
    DATA lv_m2  TYPE i.
    DATA lv_mln TYPE i.
    FIND FIRST OCCURRENCE OF '<metadata>' IN rv_code MATCH OFFSET lv_m1.
    IF sy-subrc = 0.
      FIND FIRST OCCURRENCE OF '</metadata>' IN rv_code MATCH OFFSET lv_m2.
      IF sy-subrc = 0.
        lv_mln = lv_m2 + strlen( '</metadata>' ) - lv_m1.
        REPLACE SECTION OFFSET lv_m1 LENGTH lv_mln OF rv_code WITH ''.
      ENDIF.
    ENDIF.

  ENDMETHOD.


  METHOD merge_with_current.

    IF i_type = 'CLAS' OR i_type = 'METH'.
      " Reuses the existing part-merge logic (sections + methods)
      rv_merged = zcl_code_answer_tools=>merge_class_parts(
        i_full_source    = i_full_source
        i_changed_source = i_changed_parts ).
    ELSE.
      " Programs: the envelope carries the complete <full_source>
      DATA(lv_merged) = i_changed_parts.
      REPLACE FIRST OCCURRENCE OF '<full_source>' IN lv_merged WITH ''.
      REPLACE FIRST OCCURRENCE OF '</full_source>' IN lv_merged WITH ''.
      rv_merged = lv_merged.
    ENDIF.

  ENDMETHOD.
ENDCLASS.
