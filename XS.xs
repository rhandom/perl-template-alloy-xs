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
    XPUSHs(newSVpv(exception_type, 0));
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
          SV** res = hv_store(bar, "foo", 3, newSVpv("123",0), 0);
          SV** svp = hv_fetch(bar, "foo", 3, 0);
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
    svp = av_fetch(var, i++, 0);
    SvGETMAGIC(*svp);
    SV* name = (SV*)(*svp);
    STRLEN name_len;
    char* name_c = SvPV(name, name_len);

    svp = av_fetch(var, i++, 0);
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
            if (sv_eq(*svp, newSVpv("..", 0))) {
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

    HV* seen_filters = newHV();
    while (sv_defined(ref)) {

        // check at each point if the rurned thing was a code
        if (SvROK(ref) && SvTYPE(SvRV(ref)) == SVt_PVCV) {
            ref = call_sv_with_args(ref, _self, args, G_ARRAY, Nullsv);
            if (! sv_defined(ref)) break;
        }

        // descend one chained level
        if (i >= av_len(var)) break;

        svp = hv_fetch(Args, "no_dots", 7, 0);
        bool was_dot_call = 0;
        if (svp) {
            SvGETMAGIC(*svp);
            was_dot_call = SvTRUE(*svp);
        }

        if (! was_dot_call) {
            svp = av_fetch(var, i++, 0);
            SvGETMAGIC(*svp);
            was_dot_call = sv_eq(*svp, newSVpv(".",0));
        }

        svp = av_fetch(var, i++, 0);
        if (! svp) {
            ref = &PL_sv_undef;
            break;
        }
        SvGETMAGIC(*svp);
        name = (SV*)(*svp);
        STRLEN name_len;
        char* name_c = SvPV(name, name_len);

        svp = av_fetch(var, i++, 0);
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
                //die "Shouldn't get a ". ref($name) ." during a vivify on chain";
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
                        svp = av_fetch(var, i - 5, 0);
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
                    && (svp = hv_fetch((HV*)SvRV(ref), name_c, name_len, 0))) {
                    SvGETMAGIC(*svp);
                    ref = (SV*)(*svp);
                } else {
                    SV* table = get_sv("CGI::Ex::Template::HASH_OPS", TRUE);
                    if (SvROK(table)
                        && (svp = hv_fetch((HV*)SvRV(table), name_c, name_len, FALSE))) {
                        SvGETMAGIC(*svp);
                        ref = call_sv_with_args(*svp, _self, args, G_SCALAR, ref);
                    //} elsif ($Args->{'is_namespace_during_compile'}) {
                    //    return $var; # abort - can't fold namespace variable
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
                    if (svp = av_fetch((AV*)SvRV(ref), (int)SvNV(name), 0)) {
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
//        if ($self->{'_debug_undef'}) {
//            my $chunk = $var->[$i - 2];
//            $chunk = $self->play_expr($chunk) if ref($chunk) eq 'ARRAY';
//            die "$chunk is undefined\n";
//        } else {
//            $ref = $self->undefined_any($var);
//        }
    }

    XPUSHs(ref);
    XSRETURN(1);
