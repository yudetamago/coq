
(* Test that we fail, rather than raising anomalies, on opaque terms during interpretation *)

(* https://github.com/coq/coq/pull/8064#discussion_r202497516 *)
Module Test1.
  Axiom hold : forall {A B C}, A -> B -> C.
  Definition opaque3 (x : Decimal.int) : Decimal.int := hold x (fix f (x : nat) : nat := match x with O => O | S n => S (f n) end).
  Numeral Notation Decimal.int opaque3 opaque3 : opaque_scope.
  Delimit Scope opaque_scope with opaque.
  Fail Check 1%opaque.
End Test1.

(* https://github.com/coq/coq/pull/8064#discussion_r202497990 *)
Module Test2.
  Axiom opaque4 : option Decimal.int.
  Definition opaque6 (x : Decimal.int) : option Decimal.int := opaque4.
  Numeral Notation Decimal.int opaque6 opaque6 : opaque_scope.
  Delimit Scope opaque_scope with opaque.
  Open Scope opaque_scope.
  Fail Check 1%opaque.
End Test2.

Module Test3.
  Inductive silly := SILLY (v : Decimal.uint) (f : forall A, A -> A).
  Definition to_silly (v : Decimal.uint) := SILLY v (fun _ x => x).
  Definition of_silly (v : silly) := match v with SILLY v _ => v end.
  Numeral Notation silly to_silly of_silly : silly_scope.
  Delimit Scope silly_scope with silly.
  Fail Check 1%silly.
End Test3.


Module Test4.
  Polymorphic NonCumulative Inductive punit := ptt.
  Polymorphic Definition pto_punit (v : Decimal.uint) : option punit := match Nat.of_uint v with O => Some ptt | _ => None end.
  Polymorphic Definition pto_punit_all (v : Decimal.uint) : punit := ptt.
  Polymorphic Definition pof_punit (v : punit) : Decimal.uint := Nat.to_uint 0.
  Definition to_punit (v : Decimal.uint) : option punit := match Nat.of_uint v with O => Some ptt | _ => None end.
  Definition of_punit (v : punit) : Decimal.uint := Nat.to_uint 0.
  Polymorphic Definition pto_unit (v : Decimal.uint) : option unit := match Nat.of_uint v with O => Some tt | _ => None end.
  Polymorphic Definition pof_unit (v : unit) : Decimal.uint := Nat.to_uint 0.
  Definition to_unit (v : Decimal.uint) : option unit := match Nat.of_uint v with O => Some tt | _ => None end.
  Definition of_unit (v : unit) : Decimal.uint := Nat.to_uint 0.
  Numeral Notation punit to_punit of_punit : pto.
  Numeral Notation punit pto_punit of_punit : ppo.
  Numeral Notation punit to_punit pof_punit : ptp.
  Numeral Notation punit pto_punit pof_punit : ppp.
  Numeral Notation unit to_unit of_unit : uto.
  Delimit Scope pto with pto.
  Delimit Scope ppo with ppo.
  Delimit Scope ptp with ptp.
  Delimit Scope ppp with ppp.
  Delimit Scope uto with uto.
  Check let v := 0%pto in v : punit.
  Check let v := 0%ppo in v : punit.
  Check let v := 0%ptp in v : punit.
  Check let v := 0%ppp in v : punit.
  Check let v := 0%uto in v : unit.
  Fail Check 1%uto.
  Fail Check (-1)%uto.
  Numeral Notation unit pto_unit of_unit : upo.
  Numeral Notation unit to_unit pof_unit : utp.
  Numeral Notation unit pto_unit pof_unit : upp.
  Delimit Scope upo with upo.
  Delimit Scope utp with utp.
  Delimit Scope upp with upp.
  Check let v := 0%upo in v : unit.
  Check let v := 0%utp in v : unit.
  Check let v := 0%upp in v : unit.

  Polymorphic Definition pto_punits := pto_punit_all@{Set}.
  Polymorphic Definition pof_punits := pof_punit@{Set}.
  Numeral Notation punit pto_punits pof_punits : ppps (abstract after 1).
  Delimit Scope ppps with ppps.
  Universe u.
  Constraint Set < u.
  Check let v := 0%ppps in v : punit@{u}. (* Check that universes are refreshed *)
  Fail Check let v := 1%ppps in v : punit@{u}. (* Note that universes are not refreshed here *)
End Test4.

Module Test5.
  Check S. (* At one point gave Error: Anomaly "Uncaught exception Pretype_errors.PretypeError(_, _, _)." Please report at http://coq.inria.fr/bugs/. *)
End Test5.

Module Test6.
  (* Check that numeral notations on enormous terms don't take forever to print/parse *)
  (* Ackerman definition from https://stackoverflow.com/a/10303475/377022 *)
  Fixpoint ack (n m : nat) : nat :=
    match n with
    | O => S m
    | S p => let fix ackn (m : nat) :=
                 match m with
                 | O => ack p 1
                 | S q => ack p (ackn q)
                 end
             in ackn m
    end.

  Timeout 1 Check (S (ack 4 4)). (* should be instantaneous *)

  Local Set Primitive Projections.
  Record > wnat := wrap { unwrap :> nat }.
  Definition to_uint (x : wnat) : Decimal.uint := Nat.to_uint x.
  Definition of_uint (x : Decimal.uint) : wnat := Nat.of_uint x.
  Module Export Scopes.
    Delimit Scope wnat_scope with wnat.
  End Scopes.
  Module Export Notations.
    Export Scopes.
    Numeral Notation wnat of_uint to_uint : wnat_scope (abstract after 5000).
  End Notations.
  Check let v := 0%wnat in v : wnat.
  Check wrap O.
  Timeout 1 Check wrap (ack 4 4). (* should be instantaneous *)
End Test6.

Module Test6_2.
  Import Test6.Scopes.
  Check Test6.wrap 0.
  Import Test6.Notations.
  Check let v := 0%wnat in v : Test6.wnat.
End Test6_2.

Module Test7.
  Local Set Primitive Projections.
  Record > wuint := wrap { unwrap : Decimal.uint }.
  Delimit Scope wuint_scope with wuint.
  Fail Numeral Notation wuint wrap unwrap : wuint_scope.
End Test7.

Module Test8.
  Local Set Primitive Projections.
  Record > wuint := wrap { unwrap : Decimal.uint }.
  Delimit Scope wuint_scope with wuint.
  Section with_var.
    Context (dummy : unit).
    Definition wrap' := let __ := dummy in wrap.
    Definition unwrap' := let __ := dummy in unwrap.
    Global Numeral Notation wuint wrap' unwrap' : wuint_scope.
    Check let v := 0%wuint in v : wuint.
  End with_var.
  Fail Check let v := 0%wuint in v : wuint.
  Compute wrap (Nat.to_uint 0).

  Notation wrap'' := wrap.
  Notation unwrap'' := unwrap.
  Fail Numeral Notation wuint wrap'' unwrap'' : wuint_scope.
End Test8.

Module Test9.
  Section with_let.
    Local Set Primitive Projections.
    Record > wuint := wrap { unwrap : Decimal.uint }.
    Let wrap' := wrap.
    Let unwrap' := unwrap.
    Local Notation wrap'' := wrap.
    Local Notation unwrap'' := unwrap.
    Delimit Scope wuint_scope with wuint.
    Fail Numeral Notation wuint wrap' unwrap' : wuint_scope.
    Fail Numeral Notation wuint wrap'' unwrap'' : wuint_scope.
  End with_let.
End Test9.

Module Test10.
  (* Test that it is only a warning to add abstract after to an optional parsing function *)
  Definition to_uint (v : unit) := Nat.to_uint 0.
  Definition of_uint (v : Decimal.uint) := match Nat.of_uint v with O => Some tt | _ => None end.
  Definition of_any_uint (v : Decimal.uint) := tt.
  Delimit Scope unit_scope with unit.
  Delimit Scope unit2_scope with unit2.
  Numeral Notation unit of_uint to_uint : unit_scope (abstract after 1).
  Local Set Warnings Append "+abstract-large-number-no-op".
  (* Check that there is actually a warning here *)
  Fail Numeral Notation unit of_uint to_uint : unit2_scope (abstract after 1).
  (* Check that there is no warning here *)
  Numeral Notation unit of_any_uint to_uint : unit2_scope (abstract after 1).
End Test10.
