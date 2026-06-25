CLASS zcl_code_object_tree DEFINITION
  PUBLIC
  CREATE PUBLIC.

  PUBLIC SECTION.

    " Builds a structural tree (sections / attributes / methods for a class,
    " events / forms / modules for a program) in the given container and drives
    " navigation in the owning popup's ABAP editor. Navigation is by plain text
    " search - no real ABAP parsing.
    METHODS constructor
      IMPORTING
        !io_container TYPE REF TO cl_gui_container
        !io_popup     TYPE REF TO zcl_code_popup2.

    " Rebuild the tree for an SAP object. i_type: PROG/REPS/CLAS/METH.
    " Returns abap_true when at least one node was produced.
    METHODS build_for_object
      IMPORTING
        !i_type         TYPE string
        !i_name         TYPE string
      RETURNING VALUE(rv_built) TYPE abap_bool.

  PROTECTED SECTION.
  PRIVATE SECTION.

    TYPES:
      BEGIN OF ty_map,
        key     TYPE tv_nodekey,
        program TYPE progname,
        include TYPE progname,
        search  TYPE string,
      END OF ty_map.

    DATA mo_tree    TYPE REF TO cl_gui_simple_tree.
    DATA mo_popup   TYPE REF TO zcl_code_popup2.
    DATA mt_map     TYPE STANDARD TABLE OF ty_map WITH KEY key.
    DATA mt_nodes   TYPE TABLE OF mtreesnode.
    DATA mv_key_seq TYPE i.
    DATA mv_root    TYPE tv_nodekey.

    METHODS on_node_double_click
      FOR EVENT node_double_click OF cl_gui_simple_tree
      IMPORTING !node_key.

    " Append one node to the pending node table + navigation map.
    METHODS add_node
      IMPORTING
        !i_text         TYPE string
        !i_icon         TYPE tv_image
        !i_relat        TYPE tv_nodekey OPTIONAL
        !i_folder       TYPE abap_bool DEFAULT abap_false
        !i_program      TYPE progname OPTIONAL
        !i_include      TYPE progname OPTIONAL
        !i_search       TYPE string OPTIONAL
      RETURNING VALUE(rv_key) TYPE tv_nodekey.

    METHODS build_class
      IMPORTING !i_class       TYPE string
      RETURNING VALUE(rv_built) TYPE abap_bool.

    METHODS build_section
      IMPORTING
        !i_parent  TYPE tv_nodekey
        !i_label   TYPE string
        !i_include TYPE progname
        !i_pool    TYPE progname.

    METHODS build_program
      IMPORTING !i_program     TYPE string
      RETURNING VALUE(rv_built) TYPE abap_bool.
ENDCLASS.



CLASS zcl_code_object_tree IMPLEMENTATION.


  METHOD constructor.

    mo_popup = io_popup.

    CREATE OBJECT mo_tree
      EXPORTING
        parent              = io_container
        node_selection_mode = cl_gui_simple_tree=>node_sel_mode_single
      EXCEPTIONS
        OTHERS              = 1.

    DATA lt_events TYPE cntl_simple_events.
    APPEND VALUE cntl_simple_event(
      eventid    = cl_gui_simple_tree=>eventid_node_double_click
      appl_event = space ) TO lt_events.
    mo_tree->set_registered_events( events = lt_events ).
    SET HANDLER on_node_double_click FOR mo_tree.

  ENDMETHOD.


  METHOD add_node.

    mv_key_seq = mv_key_seq + 1.
    rv_key = |N{ mv_key_seq }|.

    APPEND VALUE mtreesnode(
      node_key  = rv_key
      relatkey  = i_relat
      relatship = COND #( WHEN i_relat IS INITIAL
                          THEN 0
                          ELSE cl_gui_simple_tree=>relat_last_child )
      isfolder  = i_folder
      n_image   = i_icon
      exp_image = i_icon
      text      = i_text ) TO mt_nodes.

    APPEND VALUE ty_map(
      key     = rv_key
      program = i_program
      include = i_include
      search  = i_search ) TO mt_map.

  ENDMETHOD.


  METHOD build_for_object.

    mo_tree->delete_all_nodes( ).
    CLEAR: mt_map, mt_nodes, mv_key_seq, mv_root.

    DATA(lv_type) = i_type.
    DATA(lv_name) = i_name.
    TRANSLATE lv_type TO UPPER CASE.
    TRANSLATE lv_name TO UPPER CASE.
    CONDENSE lv_name.

    " A class can arrive as CLAS, METH, or NAME=>METHOD - always tree the class.
    DATA(lv_cls) = lv_name.
    IF lv_cls CS '=>'.
      SPLIT lv_cls AT '=>' INTO lv_cls DATA(lv_ignore).
    ENDIF.

    DATA(lv_is_class) = abap_false.
    IF lv_type CS 'CLAS' OR lv_type CS 'CLASS'
    OR lv_type CS 'METH' OR lv_name CS '=>'.
      lv_is_class = abap_true.
    ENDIF.

    IF lv_is_class = abap_true.
      rv_built = build_class( lv_cls ).
    ENDIF.

    " Either a non-class object, or a class that could not be described via RTTI
    " (e.g. local/test class) - fall back to a flat source scan.
    IF rv_built = abap_false.
      rv_built = build_program( lv_name ).
    ENDIF.

    CHECK rv_built = abap_true.

    mo_tree->add_nodes(
      EXPORTING
        table_structure_name = 'MTREESNODE'
        node_table           = mt_nodes
      EXCEPTIONS
        OTHERS               = 1 ).

    IF mv_root IS NOT INITIAL.
      mo_tree->expand_node(
        EXPORTING node_key = mv_root
        EXCEPTIONS OTHERS = 1 ).
    ENDIF.

    cl_gui_cfw=>flush( ).

  ENDMETHOD.


  METHOD build_class.

    DATA lo_type TYPE REF TO cl_abap_typedescr.
    cl_abap_typedescr=>describe_by_name(
      EXPORTING  p_name      = i_class
      RECEIVING  p_descr_ref = lo_type
      EXCEPTIONS OTHERS      = 1 ).
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.

    DATA lo_cls TYPE REF TO cl_abap_classdescr.
    TRY.
        lo_cls ?= lo_type.
      CATCH cx_sy_move_cast_error.
        RETURN.
    ENDTRY.

    " Class includes share one 30+ char prefix; only the 2-char suffix differs
    " (CP=pool, CU=public, CO=protected, CI=private). Derive the section
    " includes from the class pool name returned by the name service.
    DATA(lv_pool) = cl_oo_classname_service=>get_classpool_name( clsname = CONV #( i_class ) ).
    IF lv_pool IS INITIAL.
      RETURN.
    ENDIF.
    DATA(lv_base) = strlen( lv_pool ) - 2.
    DATA lv_prefix TYPE string.
    lv_prefix = lv_pool(lv_base).
    DATA(lv_pub)  = CONV progname( lv_prefix && 'CU' ).
    DATA(lv_pro)  = CONV progname( lv_prefix && 'CO' ).
    DATA(lv_pri)  = CONV progname( lv_prefix && 'CI' ).

    mv_root = add_node(
      i_text    = |Class { i_class }|
      i_icon    = CONV #( icon_oo_class )
      i_folder  = abap_true
      i_program = CONV #( lv_pool )
      i_include = lv_pub ).

    build_section( i_parent = mv_root i_label = 'Public Section'
                   i_include = lv_pub i_pool = CONV #( lv_pool ) ).
    build_section( i_parent = mv_root i_label = 'Protected Section'
                   i_include = lv_pro i_pool = CONV #( lv_pool ) ).
    build_section( i_parent = mv_root i_label = 'Private Section'
                   i_include = lv_pri i_pool = CONV #( lv_pool ) ).

    " Method includes (exact, from the class builder). This already yields the
    " class's own + redefined methods, each with its CM include for 1:1
    " navigation - no inheritance filtering needed.
    DATA ls_clskey TYPE seoclskey.
    DATA lt_meths  TYPE seop_methods_w_include.
    ls_clskey-clsname = i_class.
    CALL FUNCTION 'SEO_CLASS_GET_METHOD_INCLUDES'
      EXPORTING  clskey   = ls_clskey
      IMPORTING  includes = lt_meths
      EXCEPTIONS OTHERS   = 1.

    " Methods listed directly under the class node (like ACE), colour-coded by
    " visibility (public=green, protected=yellow, private=red) via RTTI lookup.
    LOOP AT lt_meths INTO DATA(ls_mi).
      DATA(lv_mname) = CONV string( ls_mi-cpdkey-cpdname ).
      DATA(lv_micon) = CONV tv_image( icon_led_inactive ).
      READ TABLE lo_cls->methods INTO DATA(ls_m)
        WITH KEY name = ls_mi-cpdkey-cpdname.
      IF sy-subrc = 0.
        CASE ls_m-visibility.
          WHEN cl_abap_classdescr=>public.    lv_micon = icon_led_green.
          WHEN cl_abap_classdescr=>protected. lv_micon = icon_led_yellow.
          WHEN cl_abap_classdescr=>private.   lv_micon = icon_led_red.
        ENDCASE.
      ENDIF.

      add_node(
        i_text    = lv_mname
        i_icon    = lv_micon
        i_relat   = mv_root
        i_program = CONV #( lv_pool )
        i_include = ls_mi-incname
        i_search  = lv_mname ).
    ENDLOOP.

    rv_built = abap_true.

  ENDMETHOD.


  METHOD build_section.

    DATA(lv_sec) = add_node(
      i_text    = i_label
      i_icon    = CONV #( icon_folder )
      i_relat   = i_parent
      i_folder  = abap_true
      i_program = i_pool
      i_include = i_include ).

    " Own declarations of this section, by light line scan (no real parsing):
    " grab the name after DATA / CLASS-DATA / CONSTANTS. Chained continuation
    " lines are skipped - good enough for a navigation tree.
    DATA lt_src TYPE STANDARD TABLE OF string WITH NON-UNIQUE DEFAULT KEY.
    READ REPORT i_include INTO lt_src.
    CHECK sy-subrc = 0.

    LOOP AT lt_src INTO DATA(lv_line).
      DATA(lv_up) = lv_line.
      CONDENSE lv_up.
      TRANSLATE lv_up TO UPPER CASE.
      DATA lv_kw   TYPE string.
      DATA lv_name TYPE string.
      CLEAR: lv_kw, lv_name.
      FIND FIRST OCCURRENCE OF
        REGEX '^(CLASS-DATA|DATA|CONSTANTS):?\s+([A-Z_/0-9]+)'
        IN lv_up SUBMATCHES lv_kw lv_name.
      CHECK lv_name IS NOT INITIAL AND lv_name <> 'BEGIN'.
      add_node(
        i_text    = lv_name
        i_icon    = CONV #( icon_parameter )
        i_relat   = lv_sec
        i_program = i_pool
        i_include = i_include
        i_search  = lv_name ).
    ENDLOOP.

  ENDMETHOD.


  METHOD build_program.

    DATA lt_src TYPE STANDARD TABLE OF string WITH NON-UNIQUE DEFAULT KEY.
    READ REPORT i_program INTO lt_src.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.

    DATA(lv_prog) = CONV progname( i_program ).
    mv_root = add_node(
      i_text    = |Program { i_program }|
      i_icon    = CONV #( icon_folder )
      i_folder  = abap_true
      i_program = lv_prog
      i_include = lv_prog ).

    DATA lv_ev_root   TYPE tv_nodekey.
    DATA lv_form_root TYPE tv_nodekey.
    DATA lv_mod_root  TYPE tv_nodekey.
    DATA lv_name      TYPE string.

    LOOP AT lt_src INTO DATA(lv_line).
      DATA(lv_up) = lv_line.
      TRANSLATE lv_up TO UPPER CASE.
      CONDENSE lv_up.

      " Event blocks (no name needed - search the keyword itself)
      IF lv_up CP 'INITIALIZATION*'
      OR lv_up CP 'START-OF-SELECTION*'
      OR lv_up CP 'END-OF-SELECTION*'
      OR lv_up CP 'LOAD-OF-PROGRAM*'
      OR lv_up CP 'TOP-OF-PAGE*'
      OR lv_up CP 'AT SELECTION-SCREEN*'
      OR lv_up CP 'AT LINE-SELECTION*'
      OR lv_up CP 'AT USER-COMMAND*'.
        IF lv_ev_root IS INITIAL.
          lv_ev_root = add_node( i_text = 'Events' i_icon = CONV #( icon_folder )
                                 i_relat = mv_root i_folder = abap_true
                                 i_program = lv_prog i_include = lv_prog ).
        ENDIF.
        DATA(lv_ev_label) = lv_up.
        REPLACE FIRST OCCURRENCE OF '.' IN lv_ev_label WITH ''.
        add_node( i_text = lv_ev_label i_icon = CONV #( icon_oo_event )
                  i_relat = lv_ev_root i_program = lv_prog i_include = lv_prog
                  i_search = lv_up ).

      ELSEIF lv_up CP 'FORM *'.
        CLEAR lv_name.
        FIND FIRST OCCURRENCE OF REGEX 'FORM\s+(\S+)' IN lv_up SUBMATCHES lv_name.
        REPLACE ALL OCCURRENCES OF '.' IN lv_name WITH ''.
        CHECK lv_name IS NOT INITIAL.
        IF lv_form_root IS INITIAL.
          lv_form_root = add_node( i_text = 'Subroutines' i_icon = CONV #( icon_folder )
                                   i_relat = mv_root i_folder = abap_true
                                   i_program = lv_prog i_include = lv_prog ).
        ENDIF.
        add_node( i_text = lv_name i_icon = CONV #( icon_oo_method )
                  i_relat = lv_form_root i_program = lv_prog i_include = lv_prog
                  i_search = |FORM { lv_name }| ).

      ELSEIF lv_up CP 'MODULE *'.
        CLEAR lv_name.
        FIND FIRST OCCURRENCE OF REGEX 'MODULE\s+(\S+)' IN lv_up SUBMATCHES lv_name.
        REPLACE ALL OCCURRENCES OF '.' IN lv_name WITH ''.
        CHECK lv_name IS NOT INITIAL.
        IF lv_mod_root IS INITIAL.
          lv_mod_root = add_node( i_text = 'Modules' i_icon = CONV #( icon_folder )
                                  i_relat = mv_root i_folder = abap_true
                                  i_program = lv_prog i_include = lv_prog ).
        ENDIF.
        add_node( i_text = lv_name i_icon = CONV #( icon_oo_method )
                  i_relat = lv_mod_root i_program = lv_prog i_include = lv_prog
                  i_search = |MODULE { lv_name }| ).
      ENDIF.
    ENDLOOP.

    rv_built = abap_true.

  ENDMETHOD.


  METHOD on_node_double_click.

    READ TABLE mt_map INTO DATA(ls_map) WITH KEY key = node_key.
    CHECK sy-subrc = 0.
    CHECK ls_map-include IS NOT INITIAL.

    mo_popup->navigate_to(
      i_program = ls_map-program
      i_include = ls_map-include
      i_search  = ls_map-search ).

  ENDMETHOD.

ENDCLASS.
