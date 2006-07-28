#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#include "ppport.h"

#define sv_defined(sv) (sv && (SvIOK(sv) || SvNOK(sv) || SvPOK(sv) || SvROK(sv)))

static SV* call_sv_with_args (SV*, SV*, SV*, SV*);

static SV* call_sv_with_args (SV* self, SV* code, SV* args, SV* optional_obj) {
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
    n = call_sv(code, G_ARRAY);
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
                croak(Nullch);
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

        case SVt_RV: // ref to a ref
            tree = (SV*)SvRV(name);
            svp  = av_fetch((AV*)SvRV(tree), 0, 0);
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
            PUTBACK;

            if (sv_defined(name)) {
                //return if $name =~ $QR_PRIVATE; # don't allow vars that begin with _
                svp = hv_fetch(self, "_vars", 5, 0);
                SvGETMAGIC(*svp);
                HV* vars = (HV*)SvRV(*svp);
                if (svp = hv_fetch(vars, name_c, name_len, 0)) {
                    SvGETMAGIC(*svp);
                    ref = (SV*)(*svp);
                } else {
                    ref = &PL_sv_undef;
                }
            }
        }
    } else if (sv_defined(name)) {
        svp = hv_fetch(Args, "is_namespace_during_compile", 27, 0);
        if (svp && SvTRUE(*svp)) {

            svp = hv_fetch(self, "NAMESPACE", 9, 0);
            SvGETMAGIC(*svp);
            HV* vars = (HV*)SvRV(*svp);
            svp = hv_fetch(vars, name_c, name_len, 0);
            SvGETMAGIC(*svp);

            ref = (SV*)(*svp);
        } else {
            //return if $name =~ $QR_PRIVATE; # don't allow vars that begin with _
            svp = hv_fetch(self, "_vars", 5, 0);
            SvGETMAGIC(*svp);
            HV* vars = (HV*)SvRV(*svp);
            if (svp = hv_fetch(vars, name_c, name_len, 0)) {
                SvGETMAGIC(*svp);
                ref = (SV*)(*svp);
                //$ref = $VOBJS->{$name} if ! defined $ref;
            } else {
                ref = &PL_sv_undef;
            }
        }
    }

    HV* seen_filters;
    while (sv_defined(ref)) {

        // check at each point if the rurned thing was a code
        if (SvROK(ref) && SvTYPE(SvRV(ref)) == SVt_PVCV) {
            ref = call_sv_with_args(_self, ref, args, Nullsv);
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
                PUTBACK;
                if (! sv_defined(name)
                    //|| $name =~ $QR_PRIVATE
                    //|| $name =~ /^\./
                    ) {
                    ref = &PL_sv_undef;
                    break;
                }
            } else {
                //die "Shouldn't get a ". ref($name) ." during a vivify on chain";
            }
        }
        //if ($name =~ $QR_PRIVATE) { # don't allow vars that begin with _
        //    $ref = undef;
        //    last;
        //}

        // allow for scalar and filter access (this happens for every non virtual method call)
        if (! SvROK(ref)) {
            SV* table = get_sv("CGI::Ex::Template::SCALAR_OPS", TRUE);
            if (SvROK(table)
                && (svp = hv_fetch((HV*)SvRV(table), name_c, name_len, FALSE))) {
                SvGETMAGIC(*svp);
                PUSHMARK(SP);
                XPUSHs(ref);
                PUTBACK;
                n = call_sv(*svp, G_SCALAR);
                SPAGAIN;
                ref = n ? POPs : &PL_sv_undef;
                PUTBACK;

            //if ($SCALAR_OPS->{$name}) {                        # normal scalar op
            //    $ref = $SCALAR_OPS->{$name}->($ref, $args ? map { $self->play_expr($_) } @$args : ());
            //
            //} elsif ($LIST_OPS->{$name}) {                     # auto-promote to list and use list op
            //    $ref = $LIST_OPS->{$name}->([$ref], $args ? map { $self->play_expr($_) } @$args : ());
            //
            //} elsif (my $filter = $self->{'FILTERS'}->{$name}    # filter configured in Template args
            //         || $FILTER_OPS->{$name}                     # predefined filters in CET
            //         || (UNIVERSAL::isa($name, 'CODE') && $name) # looks like a filter sub passed in the stash
            //         || $self->list_filters->{$name}) {          # filter defined in Template::Filters
            //
            //    if (UNIVERSAL::isa($filter, 'CODE')) {
            //        $ref = eval { $filter->($ref) }; # non-dynamic filter - no args
            //        if (my $err = $@) {
            //            $self->throw('filter', $err) if ref($err) !~ /Template::Exception$/;
            //            die $err;
            //        }
            //    } elsif (! UNIVERSAL::isa($filter, 'ARRAY')) {
            //        $self->throw('filter', "invalid FILTER entry for '$name' (not a CODE ref)");
            //
            //    } elsif (@$filter == 2 && UNIVERSAL::isa($filter->[0], 'CODE')) { # these are the TT style filters
            //        eval {
            //            my $sub = $filter->[0];
            //            if ($filter->[1]) { # it is a "dynamic filter" that will return a sub
            //                ($sub, my $err) = $sub->($self->context, $args ? map { $self->play_expr($_) } @$args : ());
            //                if (! $sub && $err) {
            //                    $self->throw('filter', $err) if ref($err) !~ /Template::Exception$/;
            //                    die $err;
            //                } elsif (! UNIVERSAL::isa($sub, 'CODE')) {
            //                    $self->throw('filter', "invalid FILTER for '$name' (not a CODE ref)")
            //                        if ref($sub) !~ /Template::Exception$/;
            //                    die $sub;
            //                }
            //            }
            //            $ref = $sub->($ref);
            //        };
            //        if (my $err = $@) {
            //            $self->throw('filter', $err) if ref($err) !~ /Template::Exception$/;
            //            die $err;
            //        }
            //    } else { # this looks like our vmethods turned into "filters" (a filter stored under a name)
            //        $self->throw('filter', 'Recursive filter alias \"$name\"') if $seen_filters{$name} ++;
            //        $var = [$name, 0, '|', @$filter, @{$var}[$i..$#$var]]; # splice the filter into our current tree
            //        $i = 2;
            //    }
            //    if (scalar keys %seen_filters
            //        && $seen_filters{$var->[$i - 5] || ''}) {
            //        $self->throw('filter', "invalid FILTER entry for '".$var->[$i - 5]."' (not a CODE ref)");
            //    }
            } else {
                ref = &PL_sv_undef;
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
                    ref = call_sv_with_args(_self, coderef, args, ref);
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
                //} elsif ($HASH_OPS->{$name}) {
                //    $ref = $HASH_OPS->{$name}->($ref, $args ? map { $self->play_expr($_) } @$args : ());
                //} elsif ($Args->{'is_namespace_during_compile'}) {
                //    return $var; # abort - can't fold namespace variable
                } else {
                    ref = &PL_sv_undef;
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
                //} elsif ($LIST_OPS->{$name}) {
                //    $ref = $LIST_OPS->{$name}->($ref, $args ? map { $self->play_expr($_) } @$args : ());
                } else {
                    ref = &PL_sv_undef;
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
