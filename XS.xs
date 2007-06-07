#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#include "ppport.h"

//#define sv_defined(sv) (sv && (SvIOK(sv) || SvNOK(sv) || SvPOK(sv) || SvROK(sv)))
#define sv_defined(sv) (sv && SvOK(sv))

#if 1
#define debug(self, data) _debug(self, data)
#else
#define debug(self, data)
#endif

///----------------------------------------------------------------///

void _debug (SV* self, SV* data) {
    dSP;
    I32 n, i;
    PUSHMARK(SP);
    XPUSHs(self);
    XPUSHs(data);
    PUTBACK;
    n = call_method("__dump_any", G_SCALAR);
    SPAGAIN;
    for (i = 0; i < n; i++) POPs;
    PUTBACK;
    return;
}

static SV* call_sv_with_args (SV* code, SV* self, AV* args, I32 flags, SV* optional_obj) {
    dSP;
    I32 n, i, j, count = av_len(args);
    SV** svp;
    PUSHMARK(SP);
    if (sv_defined(optional_obj)) XPUSHs(optional_obj);
    for (i = 0; i <= count; i++) {
        svp = av_fetch(args, i, FALSE);
        SvGETMAGIC(*svp);
        PUSHMARK(SP);
        XPUSHs(self);
        XPUSHs(*svp);
        PUTBACK;
        n = call_method("play_expr", G_ARRAY);
        SPAGAIN;
        //for (j = 0; j < n; j++) XPUSHs(POPs); // noop
        PUTBACK;
    }
    PUTBACK;
    n = call_sv(code, flags);
    SPAGAIN;

    SV* ref;
    if (n) {
        SV* result = POPs;
        if (sv_defined(result)) {
            if (n == 1) {
                ref = result;
            } else {
                AV* results = newAV();
                av_extend(results, n - 1);
                av_store(results, n - 1, result);
                for (i = n - 2; i >= 0; i--) av_store(results, i, (SV*)POPs);
                ref = newRV_noinc((SV*)results);
            }
            PUTBACK;
        } else {
            result = POPs;
            for (i = 1; i < n; i++) POPs;
            PUTBACK;
            if (sv_defined(result)) {
                SV* errsv = get_sv("@", TRUE);
                sv_setsv(errsv, result);
                (void)die(Nullch);
            } else {
                ref = &PL_sv_undef;
            }
        }
    } else {
        PUTBACK;
        ref = &PL_sv_undef;
    }

    return ref;
}

static SV* call_sv_with_resolved_args (SV* code, SV* self, AV* args, I32 flags, SV* optional_obj) {
    dSP;
    I32 n, i, j, count = av_len(args);
    SV** svp;
    PUSHMARK(SP);
    if (sv_defined(optional_obj)) XPUSHs(optional_obj);
    for (i = 0; i <= count; i++) {
        svp = av_fetch(args, i, FALSE);
        SvGETMAGIC(*svp);
        XPUSHs(*svp);
    }
    PUTBACK;
    n = call_sv(code, flags);
    SPAGAIN;

    SV* ref;
    if (n) {
        SV* result = POPs;
        if (sv_defined(result)) {
            if (n == 1) {
                ref = result;
            } else {
                AV* results = newAV();
                av_extend(results, n - 1);
                av_store(results, n - 1, result);
                for (i = n - 2; i >= 0; i--) av_store(results, i, (SV*)POPs);
                ref = newRV_noinc((SV*)results);
            }
            PUTBACK;
        } else {
            result = POPs;
            for (i = 1; i < n; i++) POPs;
            PUTBACK;
            if (sv_defined(result)) {
                SV* errsv = get_sv("@", TRUE);
                sv_setsv(errsv, result);
                (void)die(Nullch);
            } else {
                ref = &PL_sv_undef;
            }
        }
    } else {
        PUTBACK;
        ref = &PL_sv_undef;
    }

    return ref;
}

static bool name_is_private (const char* name) {
    if ((*name == '_' || *name == '.') // yuck - hard coded
         && SvTRUE(get_sv("Template::Alloy::QR_PRIVATE", FALSE))) return 1;
    return 0;
}

static void _play_foreach (SV* self, SV* ref, SV* node, SV* out_ref) {
    dSP;
    I32 i, n;
    SV** svp;

    // ref contains the variable name (if any) and the array to foreach on
    svp = av_fetch((AV*)SvRV(ref), 0, FALSE);
    SvGETMAGIC(*svp);
    SV* var = *svp;
    svp = av_fetch((AV*)SvRV(ref), 1, FALSE);
    SvGETMAGIC(*svp);
    SV* items = *svp;

    // turn items into the array that it actually will be
    PUSHMARK(SP);
    XPUSHs(self);
    XPUSHs(items);
    PUTBACK;
    n = call_method("play_expr", G_SCALAR);
    SPAGAIN;
    items = POPs;
    for (i = 1; i < n; i++) POPs;
    PUTBACK;

    // make sure we got something back
    if (! sv_defined(items) || ! SvROK(items)) return;

    // turn the items into an iterator if it isn't already one
    if (! sv_isobject(items)
        || (! sv_derived_from(items, "Template::Alloy::Iterator") // hrm - don't really like hard coded names
            && ! sv_derived_from(items, "Template::Iterator"))) {
        PUSHMARK(SP);
        XPUSHs(sv_2mortal(newSVpv("Template::Alloy::Iterator", 0))); // hrm - even worse here
        XPUSHs(items);
        PUTBACK;
        n = call_method("new", G_SCALAR);
        SPAGAIN;
        items = POPs;
        for (i = 1; i < n; i++) POPs;
        PUTBACK;

    }

    svp = av_fetch((AV*)SvRV(node), 4, FALSE);
    SvGETMAGIC(*svp);
    SV* sub_tree = *svp;

    // localize the loop object into the stash
    svp = hv_fetch((HV*)SvRV(self), "_vars", 5, FALSE);
    SvGETMAGIC(*svp);
    SV* _vars = *svp;
    HV* vars = (HV*)SvRV(_vars);
    bool loop_exists = hv_exists(vars, "loop", 4);
    SV* old_loop = (loop_exists) ? hv_delete(vars, "loop", 4, 0) : Nullsv;

    SvREFCNT_inc(items);
    hv_store(vars, "loop", 4, items, 0);

    //sv_catsv(SvRV(out_ref), sv_2mortal(newSVpv("Test", 0)));

    //_debug(self, items);

    PUSHMARK(SP);
    XPUSHs(items);
    PUTBACK;
    n = call_method("get_first", G_ARRAY); // todo - eval to catch perl errors - so we can put the stash back
    SPAGAIN;
    SV* error = (n >= 2) ? POPs : Nullsv;
    SV* item  = (n >= 1) ? POPs : Nullsv;
    I32 j;
    for (j = 2; j < n; j++) POPs;
    PUTBACK;

    // here is the iteration
    while (! SvTRUE(error)) {
        PUSHMARK(SP);
        XPUSHs(self);
        XPUSHs(var);
        XPUSHs(item);
        PUTBACK;
        n = call_method("set_variable", G_VOID);
        SPAGAIN;
        PUTBACK;

        PUSHMARK(SP);
        XPUSHs(self);
        XPUSHs(sub_tree);
        XPUSHs(out_ref);
        PUTBACK;
        n = call_method("play_tree", G_VOID | G_EVAL);
        SPAGAIN;
        PUTBACK;

        SV* errsv = get_sv("@", TRUE);
        if (SvTRUE(errsv)) {
            if (sv_isobject(errsv)
                && (sv_derived_from(errsv, "Template::Alloy::Exception")
                    || sv_derived_from(errsv, "Template::Exception"))) {
                PUSHMARK(SP);
                XPUSHs(errsv);
                PUTBACK;
                n = call_method("type", G_SCALAR); // todo - eval to catch perl errors - so we can put the stash back
                SPAGAIN;
                SV* type = POPs;
                PUTBACK;
                if (sv_eq(type, sv_2mortal(newSVpv("next", 0)))) {
                    // do nothing - fall down to the next
                } else if (sv_eq(type, sv_2mortal(newSVpv("last", 0)))) {
                    break; // exit the while loop
                } else {
                    (void)die(Nullch); // rethrow exception
                }
            } else {
                (void)die(Nullch);
            }
        }

        PUSHMARK(SP);
        XPUSHs(items);
        PUTBACK;
        n = call_method("get_next", G_ARRAY); // todo - eval to catch perl errors - so we can put the stash back
        SPAGAIN;
        error = (n >= 2) ? POPs : Nullsv;
        item  = (n >= 1) ? POPs : Nullsv;
        I32 j;
        for (j = 2; j < n; j++) POPs;
        PUTBACK;

    }

    if (SvTRUE(error) && ! sv_eq(error, sv_2mortal(newSVpv("3", 0)))) {
        SV* errsv = get_sv("@", TRUE);
        sv_setsv(errsv, error);
        (void)die(Nullch);
    }

    // restore the old loop
    hv_delete(vars, "loop", 4, G_DISCARD);
    if (loop_exists) {
        SvREFCNT_inc(old_loop);
        hv_store(vars, "loop", 4, old_loop, 0);
    }

    return;
}


//    ### if the FOREACH tag sets a var - then nothing but the loop var gets localized
//    if (defined $var) {
//        my ($item, $error) = $items->get_first;
//        while (! $error) {
//
//            $self->set_variable($var, $item);
//
//            ### execute the sub tree
//            eval { $self->play_tree($sub_tree, $out_ref) };
//            if (my $err = $@) {
//                if (UNIVERSAL::isa($err, $PACKAGE_EXCEPTION)) {
//                    if ($err->type eq 'next') {
//                        ($item, $error) = $items->get_next;
//                        next;
//                    }
//                    last if $err->type =~ /last|break/;
//                }
//                die $err;
//            }
//
//            ($item, $error) = $items->get_next;
//        }
//        die $error if $error && $error != 3; # Template::Constants::STATUS_DONE;
//    ### if the FOREACH tag doesn't set a var - then everything gets localized
//    } else {
//
//        ### localize variable access for the foreach
//        my $swap = $self->{'_vars'};
//        local $self->{'_vars'} = my $copy = {%$swap};
//
//        ### iterate use the iterator object
//        #foreach (my $i = $items->index; $i <= $#$vals; $items->index(++ $i)) {
//        my ($item, $error) = $items->get_first;
//        while (! $error) {
//
//            if (ref($item) eq 'HASH') {
//                @$copy{keys %$item} = values %$item;
//            }
//
//            ### execute the sub tree
//            eval { $self->play_tree($sub_tree, $out_ref) };
//            if (my $err = $@) {
//                if (UNIVERSAL::isa($err, $PACKAGE_EXCEPTION)) {
//                    if ($err->type eq 'next') {
//                        ($item, $error) = $items->get_next;
//                        next;
//                    }
//                    last if $err->type =~ /last|break/;
//                }
//                die $err;
//            }
//
//            ($item, $error) = $items->get_next;
//        }
//        die $error if $error && $error != 3; # Template::Constants::STATUS_DONE;
//    }
//
//    return undef;
//}


static void xs_throw (SV* self, const char* exception_type, SV* msg) {
    dSP;

    if (sv_isobject(msg)
        && (sv_derived_from(msg, "Template::Alloy::Exception")
            || sv_derived_from(msg, "Template::Exception"))) {
        SV* errsv = get_sv("@", TRUE);
        sv_setsv(errsv, msg);
        (void)die(Nullch);
    }

    PUSHMARK(SP);
    XPUSHs(self);
    XPUSHs(sv_2mortal(newSVpv(exception_type, 0)));
    XPUSHs(msg);
    PUTBACK;
    I32 n = call_method("throw", G_VOID);
    SPAGAIN;
    I32 i;
    for (i = 0; i < n; i++) POPs;
    PUTBACK;
    return;
}


///----------------------------------------------------------------///

MODULE = Template::Alloy::XS		PACKAGE = Template::Alloy::XS

PROTOTYPES: DISABLE

static int
__test_xs (self)
    SV* self;
  CODE:
    GV *gv;
    if (sv_isobject(self)) {
      HV* obj = SvSTASH((SV*) SvRV(self));
      if ((gv = gv_fetchmethod_autoload(obj, "foobar", 0))){
        PUSHMARK(SP);
        XPUSHs(self);
        PUTBACK;
        I32 n, i;
        n = call_method("foobar", G_ARRAY);
        SPAGAIN;
        SV* r = POPs;
        for (i = 1; i < n; i++) POPs;
        PUTBACK;

        if (n > 1) {
          RETVAL = -5;
        } else {
          RETVAL = SvNV(r);
          SV* foo = &PL_sv_undef;
          HV* bar = newHV();
          SV** res = hv_store(bar, "foo", 3, sv_2mortal(newSVpv("123",0)), 0);
          SV** svp = hv_fetch(bar, "foo", 3, FALSE);
          RETVAL = SvNV(*svp);
          //          RETVAL = sv_defined(r) ? 7 : 8;
        }

      } else {
        RETVAL = -1;
      }
    } else {
      RETVAL = -2;
    }
  OUTPUT:
    RETVAL


static SV*
play_expr (_self, _var, ...)
    SV* _self;
    SV* _var;
  PPCODE:
    if (! _var) XSRETURN_UNDEF;
    if (! SvROK(_var)) {
        XPUSHs(_var);
        XSRETURN(1);
    }

    HV* self = (HV*)SvRV(_self);
    AV* var  = (AV*)SvRV(_var);
    HV* Args = (items > 2 && SvROK(ST(2)) && SvTYPE(SvRV(ST(2))) == SVt_PVHV) ? (HV*)SvRV(ST(2)) : Nullhv;
    I32 i    = 0;
    I32 n;
    SV** svp;

    svp = hv_fetch(Args, "return_ref", 10, FALSE);
    bool return_ref = (svp && SvTRUE(*svp));
    I32 var_len     = av_len(var);

    // determine the top level of this particular variable access

    SV* ref;
    svp = av_fetch(var, i++, FALSE);
    SvGETMAGIC(*svp);
    SV* name = (SV*)(*svp);

    svp = av_fetch(var, i++, FALSE);
    SvGETMAGIC(*svp);
    AV* args = (SvROK(*svp) && SvTYPE(SvRV(*svp)) == SVt_PVAV) ? (AV*)SvRV(*svp) : (AV*)sv_2mortal((SV*)newAV());

    //warn "play_expr: begin \"$name\"\n" if trace;
    if (SvROK(name)) {
        if (SvTYPE(SvRV(name)) != SVt_PVAV)
            (void)die("Found a non-arrayref during play_expr");

        // see if the first item is defined - if not - its an operator tree
        svp = av_fetch((AV*)SvRV(name), 0, FALSE);
        SvGETMAGIC(*svp);
        if (! sv_defined(*svp)) {
            svp  = av_fetch((AV*)SvRV(name), 1, FALSE);
            SvGETMAGIC(*svp);
            // if it is the .. operator then just return the number of elements it created (in array context)
            if (GIMME_V == G_ARRAY && sv_eq(*svp, sv_2mortal(newSVpv("..", 0)))) {
                PUSHMARK(SP);
                XPUSHs(_self);
                XPUSHs(name);
                PUTBACK;
                n = call_method("play_operator", G_ARRAY);
                SPAGAIN;
                PUTBACK;
                XSRETURN(n);
            } else if (sv_eq(*svp, sv_2mortal(newSVpv("-temp-", 0)))) {
                svp = av_fetch((AV*)SvRV(name), 2, FALSE);
                SvGETMAGIC(*svp);
                ref = *svp;
            } else {
                PUSHMARK(SP);
                XPUSHs(_self);
                XPUSHs(name);
                PUTBACK;
                n = call_method("play_operator", G_SCALAR);
                SPAGAIN;
                ref = POPs;
                I32 j;
                for (j = 1; j < n; j++) POPs;
                PUTBACK;
            }

        } else { // a named variable access (ie via $name.foo)
            PUSHMARK(SP);
            XPUSHs(_self);
            XPUSHs(name); // we could check if name is an array - but we will let the recursive call hit
            PUTBACK;
            n = call_method("play_expr", G_SCALAR);
            SPAGAIN;
            name = POPs;
            STRLEN name_len;
            char* name_c = SvPV(name, name_len);
            name_c = SvPV(name, name_len);
            I32 j;
            for (j = 1; j < n; j++) POPs;
            PUTBACK;

            if (sv_defined(name)) {
                if (name_is_private(name_c)) { // don't allow vars that begin with _
                    XPUSHs(&PL_sv_undef);
                    XSRETURN(1);
                }
                svp = hv_fetch(self, "_vars", 5, FALSE);
                SvGETMAGIC(*svp);
                HV* vars = (HV*)SvRV(*svp);
                if (svp = hv_fetch(vars, name_c, name_len, FALSE)) {
                    SvGETMAGIC(*svp);
                    ref = *svp;
                    if (return_ref && i >= var_len && ! SvROK(ref)) {
                        XPUSHs(newRV_inc(ref));
                        XSRETURN(1);
                    }
                } else {
                    SV* table = get_sv("Template::Alloy::VOBJS", FALSE);
                    if (SvROK(table)
                        && SvTYPE(SvRV(table)) == SVt_PVHV
                        && (svp = hv_fetch((HV*)SvRV(table), name_c, name_len, FALSE))
                        && SvTRUE(*svp)) {
                        SvGETMAGIC(*svp);
                        ref = *svp;
                    } else {
                        ref = &PL_sv_undef;
                    }
                }
            }
        }
    } else if (sv_defined(name)) {

        STRLEN name_len;
        char* name_c = SvPV(name, name_len);

        if (name_is_private(name_c)) { // don't allow vars that begin with _
            XPUSHs(&PL_sv_undef);
            XSRETURN(1);
        }
        svp = hv_fetch(self, "_vars", 5, FALSE);
        SvGETMAGIC(*svp);

        HV* vars = (HV*)SvRV(*svp);
        if (svp = hv_fetch(vars, name_c, name_len, FALSE)) {
            SvGETMAGIC(*svp);
            ref = *svp;
            if (return_ref && i >= var_len && ! SvROK(ref)) {
                XPUSHs(newRV_inc(ref));
                XSRETURN(1);
            }
        }
        if (! svp || ! sv_defined(ref)) {
            if (sv_eq(name, sv_2mortal(newSVpv("template", 0)))
                       && (svp = hv_fetch(self, "_template", 9, FALSE))) {
                SvGETMAGIC(*svp);
                ref = *svp;
            } else if (sv_eq(name, sv_2mortal(newSVpv("component", 0)))
                       && (svp = hv_fetch(self, "_component", 10, FALSE))) {
                SvGETMAGIC(*svp);
                ref = *svp;
            } else {
                SV* table = get_sv("Template::Alloy::VOBJS", FALSE);
                if (SvROK(table)
                    && SvTYPE(SvRV(table)) == SVt_PVHV
                    && (svp = hv_fetch((HV*)SvRV(table), name_c, name_len, FALSE))
                    && SvTRUE(*svp)) {
                    SvGETMAGIC(*svp);
                    ref = *svp;
                } else {
                    svp = hv_fetch(self, "VMETHOD_FUNCTIONS", 17, FALSE);
                    if (svp) SvGETMAGIC(*svp);
                    SV* table = get_sv("Template::Alloy::SCALAR_OPS", TRUE);
                    if ((! sv_defined(*svp) || SvTRUE(*svp))
                        && SvROK(table)
                        && (svp = hv_fetch((HV*)SvRV(table), name_c, name_len, FALSE))) {
                        SvGETMAGIC(*svp);
                        ref = *svp;
                    } else {
                        ref = &PL_sv_undef;
                    }
                }
            }

            if (! sv_defined(ref)
                && (svp = hv_fetch(self, "LOWER_CASE_VAR_FALLBACK", 23, FALSE))) {
                SvGETMAGIC(*svp);
                if (SvTRUE(*svp)) {
                    PUSHMARK(SP);
                    XPUSHs(name);
                    PUTBACK;
                    n = call_pv("Template::Alloy::XS::__lc", G_SCALAR); // i would love to call the builtin directly (anybody know how?)
                    SPAGAIN;
                    if (n >= 1) name = POPs;
                    I32 j;
                    for (j = 1; j < n; j++) POPs;
                    PUTBACK;

                    name_c = SvPV(name, name_len);
                    if (svp = hv_fetch(vars, name_c, name_len, FALSE)) {
                        SvGETMAGIC(*svp);
                        ref = *svp;
                    }
                }
            }
        }
    }

    HV* seen_filters = (HV *)sv_2mortal((SV *)newHV());

    while (sv_defined(ref)) {

        // check at each point if the rurned thing was a code
        if (SvROK(ref) && SvTYPE(SvRV(ref)) == SVt_PVCV) {
            if (return_ref && i >= var_len) {
                XPUSHs(SvREFCNT_inc(ref));
                XSRETURN(1);
            }
            //debug(_self, _var);
            ref = call_sv_with_args(ref, _self, args, G_ARRAY, Nullsv);
            if (! sv_defined(ref)) break;
        }

        // descend one chained level
        if (i >= var_len) break;

        bool was_dot_call = 0;
        svp = hv_fetch(Args, "no_dots", 7, FALSE);
        if (svp) SvGETMAGIC(*svp);
        if (svp && SvTRUE(*svp)) {
            was_dot_call = 1;
        } else {
            svp = av_fetch(var, i++, FALSE);
            SvGETMAGIC(*svp);
            was_dot_call = sv_eq(*svp, sv_2mortal(newSVpv(".", 0)));
        }

        svp = av_fetch(var, i++, FALSE);
        if (! svp) {
            ref = &PL_sv_undef;
            break;
        }
        SvGETMAGIC(*svp);
        name = (SV*)(*svp);
        STRLEN name_len;
        char* name_c = SvPV(name, name_len);

        svp = av_fetch(var, i++, FALSE);
        if (! svp) {
            ref = &PL_sv_undef;
            break;
        }
        SvGETMAGIC(*svp);
        args = (SvROK(*svp) && SvTYPE(SvRV(*svp)) == SVt_PVAV) ? (AV*)SvRV(*svp) : (AV*)sv_2mortal((SV*)newAV());

        //warn "play_expr: nested \"$name\"\n" if trace;

        // allow for named portions of a variable name (foo.$name.bar)
        if (SvROK(name)) {
            if (SvTYPE(SvRV(name)) == SVt_PVAV) {
                PUSHMARK(SP);
                XPUSHs(_self);
                XPUSHs(name); // we could check if name is an array - but we will let the recursive call hit
                PUTBACK;
                n = call_method("play_expr", G_SCALAR);
                SPAGAIN;
                name = POPs;
                name_c = SvPV(name, name_len);
                I32 j;
                for (j = 1; j < n; j++) POPs;
                PUTBACK;
                if (! sv_defined(name)) {
                    ref = &PL_sv_undef;
                    break;
                }
            } else {
                (void)die("Shouldn't get a . ref($name) . during a vivify on chain");
            }
        }
        if (name_is_private(name_c)) { // don't allow vars that begin with _
            ref = &PL_sv_undef;
            break;
        }

        // allow for scalar and filter access (this happens for every non virtual method call)
        if (! SvROK(ref)) {
            SV* table;
            if ((table = get_sv("Template::Alloy::SCALAR_OPS", FALSE))
                && SvROK(table)
                && (svp = hv_fetch((HV*)SvRV(table), name_c, name_len, FALSE))) {
                SvGETMAGIC(*svp);
                ref = call_sv_with_args(*svp, _self, args, G_SCALAR, ref);

            } else if ((table = get_sv("Template::Alloy::LIST_OPS", FALSE)) // auto-promote to list and use list op
                && SvROK(table)
                && (svp = hv_fetch((HV*)SvRV(table), name_c, name_len, FALSE))) {
                SvGETMAGIC(*svp);
                AV* array = newAV();
                av_push(array, ref);
                ref = call_sv_with_args(*svp, _self, args, G_SCALAR, newRV_noinc((SV*)array));
            } else {
                SV* filter = Nullsv;
                if(svp = hv_fetch(self, "FILTERS", 7, FALSE)) { // filter configured in Template args
                    SvGETMAGIC(*svp);
                    table = *svp;
                    if (SvROK(table)
                        && (svp = hv_fetch((HV*)SvRV(table), name_c, name_len, FALSE))) {
                        SvGETMAGIC(*svp);
                        filter = *svp;
                    }
                }
                if (! sv_defined(filter)
                    && (table = get_sv("Template::Alloy::FILTER_OPS", FALSE)) // predefined filters in CET
                    && SvROK(table)
                    && (svp = hv_fetch((HV*)SvRV(table), name_c, name_len, FALSE))) {
                    SvGETMAGIC(*svp);
                    filter = *svp;
                }
                if (! sv_defined(filter)
                    && SvROK(name) // looks like a filter sub passed in the stash
                    && SvTYPE(SvRV(name)) == SVt_PVCV) {
                    filter = name;
                }
                if (! sv_defined(filter)) {
                    PUSHMARK(SP);
                    XPUSHs(_self);
                    PUTBACK;
                    n = call_method("list_filters", G_SCALAR); // filter defined in Template::Filters
                    SPAGAIN;
                    if (n==1) {
                        table = POPs;
                        if (SvROK(table)
                            && (svp = hv_fetch((HV*)SvRV(table), name_c, name_len, FALSE))) {
                            SvGETMAGIC(*svp);
                            filter = *svp;
                        }
                    } else {
                      I32 j;
                      for (j = 0; j < n; j++) POPs;
                    }
                    PUTBACK;
                }
                if (sv_defined(filter)) {
                    if (SvROK(filter)
                        && SvTYPE(SvRV(filter)) == SVt_PVCV) {  // non-dynamic filter - no args
                        PUSHMARK(SP);
                        XPUSHs(ref);
                        PUTBACK;
                        n = call_sv(filter, G_SCALAR | G_EVAL);
                        SPAGAIN;
                        if (n == 1) {
                          ref = POPs;
                        } else {
                          I32 j;
                          for (j = 0; j < n; j++) POPs;
                        }
                        PUTBACK;
                        if (SvTRUE(ERRSV)) xs_throw(_self, "filter", ERRSV);
                    } else if (! SvROK(filter) || SvTYPE(SvRV(filter)) != SVt_PVAV) { // invalid filter
                        SV* msg = newSVpv("invalid FILTER entry for '", 0);
                        sv_catsv(msg, name);
                        sv_catpv(msg, "' (not a CODE ref)");
                        xs_throw(_self, "filter", msg);
                    } else {
                        AV* fa = (AV*)SvRV(filter);
                        svp = av_fetch(fa, 0, FALSE);
                        if (svp) SvGETMAGIC(*svp);
                        if (av_len(fa) == 1
                            && svp
                            && SvROK(*svp)
                            && SvTYPE(SvRV(*svp)) == SVt_PVCV) { // these are the TT style filters
                            SV* coderef = *svp;
                            svp = av_fetch(fa, 1, FALSE);
                            if (svp) SvGETMAGIC(*svp);
                            if (svp && SvTRUE(*svp)) { // it is a "dynamic filter" that will return a sub
                                I32 j;
                                PUSHMARK(SP);
                                XPUSHs(_self);
                                PUTBACK;
                                n = call_method("context", G_SCALAR);
                                SPAGAIN;
                                SV* context = (n == 1) ? POPs : Nullsv;
                                if (n > 1) for (j = 1; j < n; j++) POPs;
                                PUTBACK;

                                I32 count = av_len(args);
                                AV* _args = newAV();
                                av_extend(_args, count - 1);
                                for (j = 0; j <= count; j++) {
                                    svp = av_fetch(args, j, FALSE);
                                    if (svp) {
                                      SvGETMAGIC(*svp);
                                      PUSHMARK(SP);
                                      XPUSHs(_self);
                                      XPUSHs(*svp);
                                      PUTBACK;
                                      n = call_method("play_expr", G_SCALAR);
                                      SPAGAIN;
                                      av_store(_args, j, (SV*)POPs);
                                      if (n > 1) {
                                        I32 k;
                                        for (k = 1; k < n; k++) POPs;
                                      }
                                      PUTBACK;
                                    } else {
                                      av_store(_args, j, &PL_sv_undef);
                                    }
                                }
                                PUSHMARK(SP);
                                XPUSHs(context);
                                for (j = 0; j <= av_len(_args); j++) {
                                    svp = av_fetch(_args, j, FALSE);
                                    if (svp) {
                                        SvGETMAGIC(*svp);
                                        XPUSHs(*svp);
                                    } else {
                                        XPUSHs(&PL_sv_undef);
                                    }
                                }
                                PUTBACK;
                                n = call_sv(coderef, G_ARRAY);
                                SPAGAIN;
                                if (SvTRUE(ERRSV)) {
                                    PUTBACK;
                                    xs_throw(_self, "filter", ERRSV);
                                } else if (n >= 1) {
                                    coderef = POPs;
                                    SV* err = (n >= 2) ? POPs : Nullsv;
                                    I32 j;
                                    for (j = 1; j < n; j++) POPs;
                                    PUTBACK;
                                    if (! SvTRUE(coderef) && SvTRUE(err)) xs_throw(_self, "filter", err);
                                    if (! SvROK(coderef) || SvTYPE(SvRV(coderef)) != SVt_PVCV) {
                                        if (sv_isobject(coderef)
                                            && (sv_derived_from(coderef, "Template::Alloy::Exception")
                                                || sv_derived_from(coderef, "Template::Exception"))) {
                                            xs_throw(_self, "filter", coderef);
                                        }
                                        SV* msg = newSVpv("invalid FILTER entry for '", 0);
                                        sv_catsv(msg, name);
                                        sv_catpv(msg, "' (not a CODE ref) (2)");
                                        xs_throw(_self, "filter", msg);
                                    }
                                } else {
                                    PUTBACK;
                                    SV* msg = newSVpv("invalid FILTER entry for '", 0);
                                    sv_catsv(msg, name);
                                    sv_catpv(msg, "' (not a CODE ref) (3)");
                                    xs_throw(_self, "filter", msg);
                                }
                            }
                            // at this point - coderef should be a coderef
                            PUSHMARK(SP);
                            XPUSHs(ref);
                            PUTBACK;
                            n = call_sv(coderef, G_EVAL | G_SCALAR);
                            SPAGAIN;
                            ref = (n >= 1) ? POPs : &PL_sv_undef;
                            I32 j;
                            for (j = 1; j < n; j++) POPs;
                            PUTBACK;
                            if (SvTRUE(ERRSV)) xs_throw(_self, "filter", ERRSV);

                        } else { // this looks like our vmethods turned into "filters" (a filter stored under a name)
                            svp = hv_fetch(seen_filters, name_c, name_len, FALSE);
                            if (svp && SvTRUE(*svp)) {
                                SV* msg = newSVpv("Recursive filter alias \"", 0);
                                sv_catsv(msg, name);
                                sv_catpv(msg, "\")");
                                xs_throw(_self, "filter", msg);
                            }
                            hv_store(seen_filters, name_c, name_len, newSViv(1), 0);
                            AV* newvar = newAV();
                            av_push(newvar, name);
                            av_push(newvar, newSViv(0));
                            av_push(newvar, newSVpv("|", 1));
                            I32 j;
                            // BUGS/TODO - there is a memory leak right here - the newvar doesn't seem to get released
                            for (j = 0; j <= av_len(fa); j++) {
                                svp = av_fetch(fa, j, FALSE);
                                if (svp) SvGETMAGIC(*svp);
                                av_push(newvar, svp ? *svp : &PL_sv_undef);
                            }
                            for (j = i; j <= av_len(var); j++) {
                                svp = av_fetch(var, j, FALSE);
                                if (svp) SvGETMAGIC(*svp);
                                av_push(newvar, svp ? *svp : &PL_sv_undef);
                            }
                            var = newvar;
                            var_len = av_len(var);
                            i   = 2;
                        }
                        svp = av_fetch(var, i - 5, FALSE);
                        if (svp && SvTRUE(*svp)) { // looks like its cyclic - without a coderef in sight
                            SV*    _name = *svp;
                            STRLEN _name_len;
                            char*  _name_c = SvPV(_name, _name_len);
                            svp = hv_fetch(seen_filters, _name_c, _name_len, FALSE);
                            if (svp && SvTRUE(*svp)) {
                                SV* msg = newSVpv("invalid FILTER entry for '", 0);
                                sv_catsv(msg, _name);
                                sv_catpv(msg, "' (not a CODE ref) (4)");
                                xs_throw(_self, "filter", msg);
                            }
                        }
                    }
                } else {
                    ref = &PL_sv_undef;
                }
            }

        } else {

            // method calls on objects
            if (was_dot_call && sv_isobject(ref)) {
                if (return_ref && i >= var_len) {
                    XPUSHs(SvREFCNT_inc(ref));
                    XSRETURN(1);
                }
                HV* stash = SvSTASH((SV*)SvRV(ref));
                GV* gv = gv_fetchmethod_autoload(stash, name_c, 1);
                if (! gv) {
                    char* package = sv_reftype(SvRV(ref), 1);
                    croak("Can't locate object method \"%s\" via package %s", name_c, package);
                } else {
                    ref = call_sv_with_args((SV*)GvCV(gv), _self, args, G_ARRAY, ref);
                    if (! sv_defined(ref)) break;
                    continue;
                }
            }

            // hash member access
            if (SvTYPE(SvRV(ref)) == SVt_PVHV) {
                HV* ref_hv = (HV*)SvRV(ref);
                if (was_dot_call
                    && hv_exists(ref_hv, name_c, name_len)
                    && (svp = hv_fetch(ref_hv, name_c, name_len, FALSE))) {
                    SvGETMAGIC(*svp);
                    ref = (SV*)(*svp);
                    if (return_ref && i >= var_len && ! SvROK(ref)) {
                        XPUSHs(newRV_inc(ref));
                        XSRETURN(1);
                    }
                } else {
                    SV* table = get_sv("Template::Alloy::HASH_OPS", TRUE);
                    if (SvROK(table)
                        && (svp = hv_fetch((HV*)SvRV(table), name_c, name_len, FALSE))) {
                        SvGETMAGIC(*svp);
                        ref = call_sv_with_args(*svp, _self, args, G_SCALAR, ref);
                    } else if ((svp = hv_fetch(Args, "is_namespace_during_compile", 27, FALSE))
                               && SvTRUE(*svp)) {
                        XPUSHs(_var);
                        XSRETURN(1);
                    } else {
                        if (return_ref && i >= var_len) {
                            hv_store(ref_hv, name_c, name_len, sv_newmortal(), 0);

                            svp = hv_fetch(ref_hv, name_c, name_len, FALSE);
                            SvGETMAGIC(*svp);
                            ref = (SV*)(*svp);

                            XPUSHs(newRV_inc(ref));
                            XSRETURN(1);
                        }
                        ref = &PL_sv_undef;
                    }
                }

            // array access
            } else if (SvTYPE(SvRV(ref)) == SVt_PVAV) {
                UV name_uv;
                int res;
                if ((res = grok_number(name_c, name_len, &name_uv))
                    && res & IS_NUMBER_IN_UV) { // $name =~ m{ ^ -? $QR_NUM $ }ox) {
                    AV* ref_av = (AV*)SvRV(ref);
                    I32 index  = (int)SvNV(name);
                    if (svp = av_fetch(ref_av, index, FALSE)) {
                        SvGETMAGIC(*svp);
                        ref = (SV*)(*svp);
                        if (return_ref && i >= var_len && ! SvROK(ref)) {
                            XPUSHs(newRV_inc(ref));
                            XSRETURN(1);
                        }
                    } else {
                        if (return_ref && i >= var_len) {
                            if (av_len(ref_av) < index) av_extend(ref_av, index);
                            av_store(ref_av, index, sv_newmortal());

                            svp = av_fetch(ref_av, index, FALSE);
                            SvGETMAGIC(*svp);
                            ref = (SV*)(*svp);

                            XPUSHs(newRV_inc(ref));
                            XSRETURN(1);
                        }
                        ref = &PL_sv_undef;
                    }
                } else {
                    SV* table = get_sv("Template::Alloy::LIST_OPS", TRUE);
                    if (SvROK(table)
                        && (svp = hv_fetch((HV*)SvRV(table), name_c, name_len, FALSE))) {
                        SvGETMAGIC(*svp);
                        ref = call_sv_with_args(*svp, _self, args, G_SCALAR, ref);
                    } else {
                        ref = &PL_sv_undef;
                    }
                }
            }
        }

    } // end of while

    // allow for undefinedness
    if (! sv_defined(ref)) {
        svp = hv_fetch(self, "_debug_undef", 12, FALSE);
        if (svp && SvTRUE(*svp)) {
            svp = av_fetch(var, i - 2, FALSE);
            if (svp) SvGETMAGIC(*svp);
            SV* chunk = svp ? *svp : sv_2mortal(newSVpv("UNKNOWN", 0));
            if (SvROK(chunk) && SvTYPE(SvRV(chunk)) == SVt_PVAV) {
                PUSHMARK(SP);
                XPUSHs(_self);
                XPUSHs(chunk);
                PUTBACK;
                n = call_method("play_expr", G_SCALAR);
                SPAGAIN;
                chunk = (n >= 1) ? POPs : sv_2mortal(newSVpv("UNKNOWN", 0));
                I32 j;
                for (j = 1; j < n; j++) POPs;
                PUTBACK;
            }
            SV* msg = sv_2mortal(newSVpv("", 0));
            sv_catsv(msg, (SV*)chunk);
            sv_catpv(msg, " is undefined\n");
            (void)die(SvPV_nolen(msg));
        } else {
 //            BUGS/TODO
 //            $ref = $self->undefined_any($var);
        }
    }

    XPUSHs(ref);
    XSRETURN(1);


static int
play_tree_xs (_self, _tree, _out_ref)
    SV* _self;
    SV* _tree;
    SV* _out_ref;
  PPCODE:
    if (SvROK(_self) && SvROK(_tree) && SvROK(_out_ref)) {
        HV* self    = (HV*)SvRV(_self);
        AV* tree    = (AV*)SvRV(_tree);
        SV* out_ref = (SV*)SvRV(_out_ref);
        SV* _table  = get_sv("Template::Alloy::Play::DIRECTIVES", FALSE);
        if (! SvROK(_table) || SvTYPE(SvRV(_table)) != SVt_PVHV) (void)die("Missing table");
        HV* table   = (HV*)SvRV(_table);
        I32 len     = av_len(tree) + 1;

        SV** svp;
        I32 i;
        I32 n;
        SV*    _node;
        AV*    node;
        SV*    directive;
        STRLEN directive_len;
        char*  directive_c;
        SV*    details;
        SV*    add_str;

        for (i = 0; i < len; i++) {
            svp = av_fetch(tree, i, FALSE);
            if (! svp) continue;
            SvGETMAGIC(*svp);
            _node = *svp;

            if (! SvROK(_node)) {
                if (sv_defined(_node)) sv_catsv(out_ref, _node);
                continue;
            }

            if ((svp = hv_fetch(self, "_debug_dirs", 11, FALSE))
                && SvTRUE(*svp)) {
                svp = hv_fetch(self, "_debug_off", 10, FALSE);
                if (! svp || (svp && ! SvTRUE(*svp))) {
                    PUSHMARK(SP);
                    XPUSHs(_self);
                    XPUSHs(_node);
                    PUTBACK;
                    n = call_method("debug_node", G_SCALAR);
                    SPAGAIN;
                    if (n >= 1) {
                        add_str = POPs;
                        I32 j;
                        for (j = 1; j < n; j++) POPs;
                        if (sv_defined(add_str)) sv_catsv(out_ref, add_str);
                    }
                    PUTBACK;
                }
            }

            node = (AV*)SvRV(_node);

            svp = av_fetch(node, 0, FALSE);
            if (! svp) continue;
            SvGETMAGIC(*svp);
            directive = *svp;
            directive_c = SvPV(directive, directive_len);

            svp = av_fetch(node, 3, FALSE);
            if (! svp) continue;
            SvGETMAGIC(*svp);
            details = *svp;

            svp = hv_fetch(table, directive_c, directive_len, FALSE);
            if (! svp) continue;

            // attempt to handle FOREACH natively
            //if (sv_eq(directive, sv_2mortal(newSVpv("FOREACH", 0)))
            //    || sv_eq(directive, sv_2mortal(newSVpv("FOR", 0)))) {
            //    //if (*directive_c == 'FOREACH' || *directive_c == 'FOR') {
            //    _play_foreach(_self, details, _node, _out_ref);
            //
            //} else {

                PUSHMARK(SP);
                XPUSHs(_self);
                XPUSHs(details);
                XPUSHs(_node);
                XPUSHs(_out_ref);
                PUTBACK;
                n = call_sv(*svp, G_VOID);
                SPAGAIN;
                if (n >= 1) {
                    I32 j;
                    for (j = 0; j < n; j++) POPs;
                }
                PUTBACK;
            //}
        }

        XPUSHi(1);
    } else {
        XPUSHi(0);
    }
    XSRETURN(1);


static SV*
set_variable (_self, _var, val, ...)
    SV* _self;
    SV* _var;
    SV* val;
  PPCODE:
    if (! _var) XSRETURN_UNDEF;

    HV* self = (HV*)SvRV(_self);
    AV* var;
    if (SvROK(_var)) {
        var = (AV*)SvRV(_var);
    } else { // allow for the parse tree to store literals - the literal is used as a name (like [% 'a' = 'A' %])
        var = newAV();
        av_push(var, _var);
        av_push(var, newSViv(0));
    }
    HV* Args = (items > 3 && SvROK(ST(3)) && SvTYPE(SvRV(ST(3))) == SVt_PVHV) ? (HV*)SvRV(ST(3)) : Nullhv;
    I32 i    = 0;
    I32 n;
    SV** svp;
    I32 var_len = av_len(var);

    // determine the top level of this particular variable access

    SV* ref;
    svp = av_fetch(var, i++, FALSE);
    SvGETMAGIC(*svp);
    SV* name = (SV*)(*svp);
    STRLEN name_len;
    char* name_c = SvPV(name, name_len);

    svp = av_fetch(var, i++, FALSE);
    SvGETMAGIC(*svp);
    AV* args = (SvROK(*svp) && SvTYPE(SvRV(*svp)) == SVt_PVAV) ? (AV*)SvRV(*svp) : (AV*)sv_2mortal((SV*)newAV());

    if (SvROK(name)) {
        // non-named types can't be set
        if (SvTYPE(SvRV(name)) != SVt_PVAV) {
            XPUSHs(&PL_sv_undef);
            XSRETURN(1);
        }

        // operators can't be set either
        svp = av_fetch((AV*)SvRV(name), 0, FALSE);
        SvGETMAGIC(*svp);
        if (! sv_defined(*svp)) {
            XPUSHs(&PL_sv_undef);
            XSRETURN(1);
        }

        // named access (ie via $name.foo)
        PUSHMARK(SP);
        XPUSHs(_self);
        XPUSHs(name); // we could check if name is an array - but we will let the recursive call hit
        PUTBACK;
        n = call_method("play_expr", G_SCALAR);
        SPAGAIN;
        name = POPs;
        name_c = SvPV(name, name_len);
        I32 j;
        for (j = 1; j < n; j++) POPs;
        PUTBACK;

        if (! sv_defined(name)         // no defined
            || name_is_private(name_c) // don't allow vars that begin with _
            || ! (svp = hv_fetch(self, "_vars", 5, FALSE)) // no entry
            ) {
            XPUSHs(&PL_sv_undef);
            XSRETURN(1);
        }

        SvGETMAGIC(*svp);
        ref = *svp;

        HV* ref_hv = (HV*)SvRV(ref);
        if (svp = hv_fetch(ref_hv, name_c, name_len, FALSE))
            SvGETMAGIC(*svp);

        if (i > var_len) {
            SV* newval = newSVsv(val);

            if (svp) SvSetSV_nosteal(*svp, newval);
            else     hv_store(ref_hv, name_c, name_len, newval, 0);

            XPUSHs(val);
            XSRETURN(1);
        }

        if (! svp || ! SvROK(*svp)) {
            HV* newlevel = newHV();
            hv_store(ref_hv, name_c, name_len, newRV_noinc((SV*)newlevel), 0);
            svp = hv_fetch(ref_hv, name_c, name_len, FALSE);
            SvGETMAGIC(*svp);
        }
        ref = *svp;

    } else if (sv_defined(name)) {
        if (name_is_private(name_c) // don't allow vars that begin with _
            || ! (svp = hv_fetch(self, "_vars", 5, FALSE)) // no entry
            ) {
            XPUSHs(&PL_sv_undef);
            XSRETURN(1);
        }

        SvGETMAGIC(*svp);
        ref = *svp;

        HV* ref_hv = (HV*)SvRV(ref);
        if (svp = hv_fetch(ref_hv, name_c, name_len, FALSE))
            SvGETMAGIC(*svp);

        if (i > var_len) {
            SV* newval = newSVsv(val);

            if (svp) SvSetSV_nosteal(*svp, newval);
            else     hv_store(ref_hv, name_c, name_len, newval, 0);

            XPUSHs(newval);
            XSRETURN(1);
        }

        if (! svp || ! SvROK(*svp)) {
            HV* newlevel = newHV();
            hv_store(ref_hv, name_c, name_len, newRV_noinc((SV*)newlevel), 0);
            svp = hv_fetch(ref_hv, name_c, name_len, FALSE);
            SvGETMAGIC(*svp);
        }
        ref = *svp;

    }

    while (sv_defined(ref)) {

        // check at each point if the returned thing was a code
        if (SvROK(ref) && SvTYPE(SvRV(ref)) == SVt_PVCV) {
            ref = call_sv_with_args(ref, _self, args, G_ARRAY, Nullsv);
            if (! sv_defined(ref)) {
                XPUSHs(&PL_sv_undef);
                XSRETURN(1);
            }
        }

        // descend one chained level
        if (i >= var_len) break;

        bool was_dot_call = 0;
        svp = hv_fetch(Args, "no_dots", 7, FALSE);
        if (svp) SvGETMAGIC(*svp);
        if (svp && SvTRUE(*svp)) {
            was_dot_call = 1;
        } else {
            svp = av_fetch(var, i++, FALSE);
            SvGETMAGIC(*svp);
            was_dot_call = sv_eq(*svp, sv_2mortal(newSVpv(".", 0)));
        }

        svp = av_fetch(var, i++, FALSE);
        if (! svp) {
            ref = &PL_sv_undef;
            break;
        }
        SvGETMAGIC(*svp);
        name = (SV*)(*svp);
        STRLEN name_len;
        char* name_c = SvPV(name, name_len);

        svp = av_fetch(var, i++, FALSE);
        if (! svp) {
            ref = &PL_sv_undef;
            break;
        }
        SvGETMAGIC(*svp);
        args = (SvROK(*svp) && SvTYPE(SvRV(*svp)) == SVt_PVAV) ? (AV*)SvRV(*svp) : (AV*)sv_2mortal((SV*)newAV());

        // allow for named portions of a variable name (foo.$name.bar)
        if (SvROK(name)) {
            if (SvTYPE(SvRV(name)) == SVt_PVAV) {
                PUSHMARK(SP);
                XPUSHs(_self);
                XPUSHs(name); // we could check if name is an array - but we will let the recursive call hit
                PUTBACK;
                n = call_method("play_expr", G_SCALAR);
                SPAGAIN;
                name = POPs;
                name_c = SvPV(name, name_len);
                I32 j;
                for (j = 1; j < n; j++) POPs;
                PUTBACK;
                if (! sv_defined(name)) {
                    XPUSHs(&PL_sv_undef);
                    XSRETURN(1);
                }
            } else {
                (void)die("Shouldn't get a .ref($name). during a vivify on chain");
            }
        }
        if (name_is_private(name_c)) { // don't allow vars that begin with _
            XPUSHs(&PL_sv_undef);
            XSRETURN(1);
        }

        // scalar access
        if (! SvROK(ref)) {
            XPUSHs(&PL_sv_undef);
            XSRETURN(1);

        // method calls on objects
        } else if (was_dot_call && sv_isobject(ref)) {
            HV*  stash = SvSTASH((SV*) SvRV(ref));
            GV*  gv    = gv_fetchmethod_autoload(stash, name_c, 1);
            if (! gv) {
                char* package = sv_reftype(SvRV(ref), 1);
                croak("Can't locate object method \"%s\" via package \"%s\"", name_c, package);
            } else {
                bool lvalueish = FALSE;
                if (i >= var_len) {
                    lvalueish = TRUE;
                    AV* newargs = newAV();
                    I32 j;
                    for (j = 0; j <= av_len(args); j++) {
                        svp = av_fetch(args, j, FALSE);
                        if (svp) SvGETMAGIC(*svp);
                        av_push(newargs, svp ? *svp : &PL_sv_undef);
                    }
                    av_push(newargs, val);
                    args = newargs; //newRV_noinc((SV*)newargs);
                }
                ref = call_sv_with_args((SV*)GvCV(gv), _self, args, G_ARRAY, ref);
                if (lvalueish || ! sv_defined(ref)) {
                    XPUSHs(&PL_sv_undef);
                    XSRETURN(1);
                }
                continue;
            }
        }

        // hash member access
        if (SvTYPE(SvRV(ref)) == SVt_PVHV) {

            HV* ref_hv = (HV*)SvRV(ref);
            if (svp = hv_fetch(ref_hv, name_c, name_len, FALSE))
                SvGETMAGIC(*svp);

            if (i > var_len) {
                SV* newval = newSVsv(val);

                if (svp) SvSetSV_nosteal(*svp, newval);
                else     hv_store(ref_hv, name_c, name_len, newval, 0);

                XPUSHs(val);
                XSRETURN(1);
            }

            if (! svp || ! SvROK(*svp)) {
                HV* newlevel = newHV();
                hv_store(ref_hv, name_c, name_len, newRV_noinc((SV*)newlevel), 0);
                svp = hv_fetch(ref_hv, name_c, name_len, FALSE);
                SvGETMAGIC(*svp);
            }
            ref = *svp;
            continue;

        // array access
        } else if (SvTYPE(SvRV(ref)) == SVt_PVAV) {
            UV name_uv;
            int res;
            if ((res = grok_number(name_c, name_len, &name_uv))
                && res & IS_NUMBER_IN_UV) { // $name =~ m{ ^ -? $QR_NUM $ }ox) {

                AV* ref_av = (AV*)SvRV(ref);
                if (svp = av_fetch(ref_av, (int)SvNV(name), FALSE))
                    SvGETMAGIC(*svp);

                if (i > var_len) {
                    SV* newval = newSVsv(val);

                    if (svp) SvSetSV_nosteal(*svp, newval);
                    else     av_store(ref_av, (int)SvNV(name), newval);

                    XPUSHs(val);
                    XSRETURN(1);
                }

                if (! svp || ! SvROK(*svp)) {
                    HV* newlevel = newHV();
                    av_store(ref_av, (int)SvNV(name), newRV_noinc((SV*)newlevel));
                    svp = av_fetch(ref_av, (int)SvNV(name), FALSE);
                    SvGETMAGIC(*svp);
                }
                ref = *svp;
                continue;

            } else {
                XPUSHs(&PL_sv_undef);
                XSRETURN(1);
            }
        } else {
            XPUSHs(&PL_sv_undef);
            XSRETURN(1);
        }
    }

    XPUSHs(&PL_sv_undef);
    XSRETURN(1);
