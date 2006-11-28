#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#include "ppport.h"

#define sv_defined(sv) (sv && (SvIOK(sv) || SvNOK(sv) || SvPOK(sv) || SvROK(sv)))

///----------------------------------------------------------------///

static SV* call_sv_with_args (SV* code, SV* self, SV* args, I32 flags, SV* optional_obj) {
    dSP;
    I32 n;
    I32 i;
    I32 j;
    SV** svp;
    AV* args_real = newAV();
    if (SvROK(args)) {
        AV* args_fake = (AV*)SvRV(args);
        for (i = 0; i <= av_len(args_fake); i++) {
            svp = av_fetch(args_fake, i, FALSE);
            SvGETMAGIC(*svp);
            PUSHMARK(SP);
            XPUSHs(self);
            XPUSHs(*svp);
            PUTBACK;
            n = call_method("play_expr", G_ARRAY);
            SPAGAIN;
            for (j = 0; j < n; j++) av_push(args_real, POPs);
            PUTBACK;
        }
    }
    PUSHMARK(SP);
    if (sv_defined(optional_obj)) XPUSHs(optional_obj);
    for (i = 0; i <= av_len(args_real); i++) {
        svp = av_fetch(args_real, i, FALSE);
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
    return (*name == '_' || *name == '.') ? 1 : 0;
}

static void xs_throw (SV* self, const char* exception_type, SV* msg) {
    dSP;

    if (sv_isobject(msg)
        && (sv_derived_from(msg, "CGI::Ex::Template::Exception")
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
    PUTBACK;
    return;
}


///----------------------------------------------------------------///

MODULE = CGI::Ex::Template::XS		PACKAGE = CGI::Ex::Template::XS

PROTOTYPES: DISABLE

static int
test_xs (self)
    SV* self;
  CODE:
    GV *gv;
    if (sv_isobject(self)) {
      HV* obj = SvSTASH((SV*) SvRV(self));
      if ((gv = gv_fetchmethod_autoload(obj, "foobar", 1))){
        PUSHMARK(SP);
        XPUSHs(self);
        PUTBACK;
        I32 n;
        n = call_method("foobar", G_ARRAY);
        SPAGAIN;
        SV* r = POPs;
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

    // determine the top level of this particular variable access

    SV* ref;
    svp = av_fetch(var, i++, FALSE);
    SvGETMAGIC(*svp);
    SV* name = (SV*)(*svp);
    STRLEN name_len;
    char* name_c = SvPV(name, name_len);

    svp = av_fetch(var, i++, FALSE);
    SvGETMAGIC(*svp);
    SV* args = (SV*)(*svp);

    //warn "play_expr: begin \"$name\"\n" if trace;
    if (SvROK(name)) {
        SV* tree;
        switch(SvTYPE(SvRV(name))) {
        case SVt_IV: // ref to a literal int
            ref = (SV*)SvRV(name);
            break;

        case SVt_NV: // ref to a literal num
            ref = (SV*)SvRV(name);
            break;

        case SVt_PV: // ref to a scalar string
            ref = (SV*)SvRV(name);
            break;

        case SVt_PVMG: // also a ref to some strings
            ref = (SV*)SvRV(name);
            break;

        case SVt_RV: // ref to a ref
            tree = (SV*)SvRV(name);
            svp  = av_fetch((AV*)SvRV(tree), 0, FALSE);
            SvGETMAGIC(*svp);
            // if it is the .. operator then just return the number of elements it created
            if (sv_eq(*svp, sv_2mortal(newSVpv("..", 0)))) {
                PUSHMARK(SP);
                XPUSHs(_self);
                XPUSHs(tree);
                PUTBACK;
                n = call_method("play_operator", G_ARRAY);
                SPAGAIN;
                PUTBACK;
                XSRETURN(n);
            } else {
                PUSHMARK(SP);
                XPUSHs(_self);
                XPUSHs(tree);
                PUTBACK;
                n = call_method("play_operator", G_SCALAR);
                SPAGAIN;
                ref = POPs;
                PUTBACK;
            }
            break;

        default: // a named variable access (ie via $name.foo)
            PUSHMARK(SP);
            XPUSHs(_self);
            XPUSHs(name); // we could check if name is an array - but we will let the recursive call hit
            PUTBACK;
            n = call_method("play_expr", G_SCALAR);
            SPAGAIN;
            name = POPs;
            name_c = SvPV(name, name_len);
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
                } else {
                    SV* table = get_sv("CGI::Ex::Template::VOBJS", FALSE);
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
        svp = hv_fetch(Args, "is_namespace_during_compile", 27, FALSE);
        if (svp && SvTRUE(*svp)) {

            if (svp = hv_fetch(self, "NAMESPACE", 9, FALSE)) {
                SvGETMAGIC(*svp);
                HV* vars = (HV*)SvRV(*svp);
                if (svp = hv_fetch(vars, name_c, name_len, FALSE)) {
                    SvGETMAGIC(*svp);
                    ref = (SV*)(*svp);
                } else {
                    ref = &PL_sv_undef;
                }
            } else {
                ref = &PL_sv_undef;
            }
        } else {
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
            } else {
                SV* table = get_sv("CGI::Ex::Template::VOBJS", FALSE);
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

    HV* seen_filters = (HV *)sv_2mortal((SV *)newHV());

    while (sv_defined(ref)) {

        // check at each point if the rurned thing was a code
        if (SvROK(ref) && SvTYPE(SvRV(ref)) == SVt_PVCV) {
            ref = call_sv_with_args(ref, _self, args, G_ARRAY, Nullsv);
            if (! sv_defined(ref)) break;
        }

        // descend one chained level
        if (i >= av_len(var)) break;

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
        args = (SV*)(*svp);

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
            if ((table = get_sv("CGI::Ex::Template::SCALAR_OPS", FALSE))
                && SvROK(table)
                && (svp = hv_fetch((HV*)SvRV(table), name_c, name_len, FALSE))) {
                SvGETMAGIC(*svp);
                ref = call_sv_with_args(*svp, _self, args, G_SCALAR, ref);

            } else if ((table = get_sv("CGI::Ex::Template::LIST_OPS", FALSE)) // auto-promote to list and use list op
                && SvROK(table)
                && (svp = hv_fetch((HV*)SvRV(table), name_c, name_len, FALSE))) {
                SvGETMAGIC(*svp);
                AV* array = newAV();
                av_push(array, ref);
                ref = call_sv_with_args(*svp, _self, args, G_SCALAR, newRV_noinc((SV*)array));
            } else {
                SV* filter = &PL_sv_undef;
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
                    && (table = get_sv("CGI::Ex::Template::FILTER_OPS", FALSE)) // predefined filters in CET
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
                        if (n == 1) ref = POPs;
                        PUTBACK;
                        if (SvTRUE(ERRSV)) xs_throw(_self, "filter", ERRSV);
                    } else if (! SvROK(filter) || SvTYPE(SvRV(filter)) != SVt_PVAV) { // invalid filter
                        SV* msg = sv_2mortal(newSVpv("invalid FILTER entry for '", 0));
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
                                PUSHMARK(SP);
                                XPUSHs(_self);
                                PUTBACK;
                                n = call_method("context", G_SCALAR);
                                SPAGAIN;
                                SV* context = (n == 1) ? POPs : Nullsv;
                                PUTBACK;
                                PUSHMARK(SP);
                                XPUSHs(context);
                                if (args && SvROK(args)) {
                                    I32 j;
                                    for (j = 0; j <= av_len((AV*)SvRV(args)); j++) {
                                        svp = av_fetch((AV*)SvRV(args), j, FALSE);
                                        if (svp) {
                                            SvGETMAGIC(*svp);
                                            XPUSHs(*svp);
                                        } else {
                                            XPUSHs(&PL_sv_undef);
                                        }
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
                                    PUTBACK;
                                    if (! SvTRUE(coderef) && SvTRUE(err)) xs_throw(_self, "filter", err);
                                    if (! SvROK(coderef) || SvTYPE(SvRV(coderef)) != SVt_PVCV) {
                                        if (sv_isobject(coderef)
                                            && (sv_derived_from(coderef, "CGI::Ex::Template::Exception")
                                                || sv_derived_from(coderef, "Template::Exception"))) {
                                            xs_throw(_self, "filter", coderef);
                                        }
                                        SV* msg = sv_2mortal(newSVpv("invalid FILTER entry for '", 0));
                                        sv_catsv(msg, name);
                                        sv_catpv(msg, "' (not a CODE ref) (2)");
                                        xs_throw(_self, "filter", msg);
                                    }
                                } else {
                                    PUTBACK;
                                    SV* msg = sv_2mortal(newSVpv("invalid FILTER entry for '", 0));
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
                            PUTBACK;
                            if (SvTRUE(ERRSV)) xs_throw(_self, "filter", ERRSV);

                        } else { // this looks like our vmethods turned into "filters" (a filter stored under a name)
                            svp = hv_fetch(seen_filters, name_c, name_len, FALSE);
                            if (svp && SvTRUE(*svp)) {
                                SV* msg = sv_2mortal(newSVpv("Recursive filter alias \"", 0));
                                sv_catsv(msg, name);
                                sv_catpv(msg, "\")");
                                xs_throw(_self, "filter", msg);
                            }
                            hv_store(seen_filters, name_c, name_len, newSViv(1), 0);
                            AV* newvar = newAV();
                            av_push(newvar, name);
                            av_push(newvar, newSViv(0));
                            av_push(newvar, sv_2mortal(newSVpv("|", 1)));
                            I32 j;
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
                            i   = 2;
                        }
                        svp = av_fetch(var, i - 5, FALSE);
                        if (svp && SvTRUE(*svp)) { // looks like its cyclic - without a coderef in sight
                            SV*    _name = *svp;
                            STRLEN _name_len;
                            char*  _name_c = SvPV(_name, _name_len);
                            svp = hv_fetch(seen_filters, _name_c, _name_len, FALSE);
                            if (svp && SvTRUE(*svp)) {
                                SV* msg = sv_2mortal(newSVpv("invalid FILTER entry for '", 0));
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
                HV* stash = SvSTASH((SV*) SvRV(ref));
                GV* gv = gv_fetchmethod_autoload(stash, name_c, 1);
                if (! gv) {
                    char* package = sv_reftype(SvRV(ref), 1);
                    croak("Can't locate object method \"%s\" via package %s", name_c, package);
                } else {
                    SV* coderef = newRV_noinc((SV*)GvCV(gv));
                    ref = call_sv_with_args(coderef, _self, args, G_ARRAY, ref);
                    if (! sv_defined(ref)) break;
                    continue;
                }
            }

            // hash member access
            if (SvTYPE(SvRV(ref)) == SVt_PVHV) {
                if (was_dot_call
                    && hv_exists((HV*)SvRV(ref), name_c, name_len)
                    && (svp = hv_fetch((HV*)SvRV(ref), name_c, name_len, FALSE))) {
                    SvGETMAGIC(*svp);
                    ref = (SV*)(*svp);
                } else {
                    SV* table = get_sv("CGI::Ex::Template::HASH_OPS", TRUE);
                    if (SvROK(table)
                        && (svp = hv_fetch((HV*)SvRV(table), name_c, name_len, FALSE))) {
                        SvGETMAGIC(*svp);
                        ref = call_sv_with_args(*svp, _self, args, G_SCALAR, ref);
                    } else if ((svp = hv_fetch(Args, "is_namespace_during_compile", 27, FALSE))
                               && SvTRUE(*svp)) {
                        XPUSHs(_var);
                        XSRETURN(1);
                    } else {
                        ref = &PL_sv_undef;
                    }
                }

            // array access
            } else if (SvTYPE(SvRV(ref)) == SVt_PVAV) {
                UV name_uv;
                int res;
                if ((res = grok_number(name_c, name_len, &name_uv))
                    && res & IS_NUMBER_IN_UV) { // $name =~ m{ ^ -? $QR_NUM $ }ox) {
                    if (svp = av_fetch((AV*)SvRV(ref), (int)SvNV(name), FALSE)) {
                        SvGETMAGIC(*svp);
                        ref = (SV*)(*svp);
                    } else {
                        ref = &PL_sv_undef;
                    }
                } else {
                    SV* table = get_sv("CGI::Ex::Template::LIST_OPS", TRUE);
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
                PUTBACK;
            }
            SV* msg = sv_2mortal(newSVpv("", 0));
            sv_catsv(msg, (SV*)chunk);
            sv_catpv(msg, " is undefined\n");
            (void)die(SvPV_nolen(msg));
        } else {
 //            TODO
 //            $ref = $self->undefined_any($var);
        }
    }

    XPUSHs(ref);
    XSRETURN(1);


static int
execute_tree (_self, _tree, _out_ref)
    SV* _self;
    SV* _tree;
    SV* _out_ref;
  PPCODE:
    if (SvROK(_self) && SvROK(_tree) && SvROK(_out_ref)) {
        HV* self    = (HV*)SvRV(_self);
        AV* tree    = (AV*)SvRV(_tree);
        SV* out_ref = (SV*)SvRV(_out_ref);
        SV* _table  = get_sv("CGI::Ex::Template::DIRECTIVES", FALSE);
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
        AV*    directive_node;
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
            directive_node = (AV*)SvRV(*svp);

            svp = av_fetch(directive_node, 1, FALSE);
            if (! svp) continue;

            PUSHMARK(SP);
            XPUSHs(_self);
            XPUSHs(details);
            XPUSHs(_node);
            XPUSHs(_out_ref);
            PUTBACK;
            n = call_sv(*svp, G_SCALAR);
            SPAGAIN;
            if (n >= 1) {
                add_str = POPs;
                if (sv_defined(add_str)) sv_catsv(out_ref, add_str);
            }
            PUTBACK;
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

    // determine the top level of this particular variable access

    SV* ref;
    svp = av_fetch(var, i++, FALSE);
    SvGETMAGIC(*svp);
    SV* name = (SV*)(*svp);
    STRLEN name_len;
    char* name_c = SvPV(name, name_len);

    svp = av_fetch(var, i++, FALSE);
    SvGETMAGIC(*svp);
    SV* args = (SV*)(*svp);

    if (SvROK(name)) {
        if (SvTYPE(SvRV(name)) == SVt_PVAV) { // named access (ie via $name.foo)
            PUSHMARK(SP);
            XPUSHs(_self);
            XPUSHs(name); // we could check if name is an array - but we will let the recursive call hit
            PUTBACK;
            n = call_method("play_expr", G_SCALAR);
            SPAGAIN;
            name = POPs;
            name_c = SvPV(name, name_len);
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

            if (av_len(var) <= i) {
                SV* newval = newSVsv(val);
                hv_store((HV*)SvRV(ref), name_c, name_len, newval, 0);
                XPUSHs(val);
                XSRETURN(1);
            }

            svp = hv_fetch((HV*)SvRV(ref), name_c, name_len, FALSE);
            if (! svp || ! SvROK(*svp)) {
                HV* newlevel = newHV();
                hv_store((HV*)SvRV(ref), name_c, name_len, newRV_noinc((SV*)newlevel), 0);
                svp = hv_fetch((HV*)SvRV(ref), name_c, name_len, FALSE);
            }
            SvGETMAGIC(*svp);
            ref = *svp;

        } else { // all other types can't be set
            XPUSHs(&PL_sv_undef);
            XSRETURN(1);
        }
    } else if (sv_defined(name)) {
        if (name_is_private(name_c) // don't allow vars that begin with _
            || ! (svp = hv_fetch(self, "_vars", 5, FALSE)) // no entry
            ) {
            XPUSHs(&PL_sv_undef);
            XSRETURN(1);
        }

        SvGETMAGIC(*svp);
        ref = *svp;

        if (av_len(var) <= i) {
            SV* newval = newSVsv(val);
            hv_store((HV*)SvRV(ref), name_c, name_len, newval, 0);
            XPUSHs(newval);
            XSRETURN(1);
        }

        svp = hv_fetch((HV*)SvRV(ref), name_c, name_len, FALSE);
        if (! svp || ! SvROK(*svp)) {
            HV* newlevel = newHV();
            hv_store((HV*)SvRV(ref), name_c, name_len, newRV_noinc((SV*)newlevel), 0);
            svp = hv_fetch((HV*)SvRV(ref), name_c, name_len, FALSE);
        }
        SvGETMAGIC(*svp);
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
        if (i >= av_len(var)) break;

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
        args = (SV*)(*svp);

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
                if (i >= av_len(var)) {
                    lvalueish = TRUE;
                    AV* newargs = newAV();
                    if (SvROK(args) && SvTYPE(SvRV(args)) == SVt_PVAV) {
                        I32 j;
                        for (j = 0; j <= av_len((AV*)SvRV(args)); j++) {
                            svp = av_fetch((AV*)SvRV(args), j, FALSE);
                            if (svp) SvGETMAGIC(*svp);
                            av_push(newargs, svp ? *svp : &PL_sv_undef);
                        }
                    }
                    av_push(newargs, val);
                    args = newRV_noinc((SV*)newargs);
                }
                SV* coderef = newRV_noinc((SV*)GvCV(gv));
                ref = call_sv_with_args(coderef, _self, args, G_ARRAY, ref);
                if (lvalueish || ! sv_defined(ref)) {
                    XPUSHs(&PL_sv_undef);
                    XSRETURN(1);
                }
                continue;
            }
        }

        // hash member access
        if (SvTYPE(SvRV(ref)) == SVt_PVHV) {
            if (av_len(var) <= i) {
                SV* newval = newSVsv(val);
                hv_store((HV*)SvRV(ref), name_c, name_len, newval, 0);
                XPUSHs(val);
                XSRETURN(1);
            }

            svp = hv_fetch((HV*)SvRV(ref), name_c, name_len, FALSE);
            if (! svp || ! SvROK(*svp)) {
                HV* newlevel = newHV();
                hv_store((HV*)SvRV(ref), name_c, name_len, newRV_noinc((SV*)newlevel), 0);
                svp = hv_fetch((HV*)SvRV(ref), name_c, name_len, FALSE);
            }
            SvGETMAGIC(*svp);
            ref = *svp;
            continue;

        // array access
        } else if (SvTYPE(SvRV(ref)) == SVt_PVAV) {
            UV name_uv;
            int res;
            if ((res = grok_number(name_c, name_len, &name_uv))
                && res & IS_NUMBER_IN_UV) { // $name =~ m{ ^ -? $QR_NUM $ }ox) {

                if (av_len(var) <= i) {
                    SV* newval = newSVsv(val);
                    av_store((AV*)SvRV(ref), (int)SvNV(name), newval);
                    XPUSHs(val);
                    XSRETURN(1);
                }

                svp = av_fetch((AV*)SvRV(ref), (int)SvNV(name), FALSE);
                if (! svp || ! SvROK(*svp)) {
                    HV* newlevel = newHV();
                    av_store((AV*)SvRV(ref), (int)SvNV(name), newRV_noinc((SV*)newlevel));
                    svp = av_fetch((AV*)SvRV(ref), (int)SvNV(name), FALSE);
                }
                SvGETMAGIC(*svp);
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
