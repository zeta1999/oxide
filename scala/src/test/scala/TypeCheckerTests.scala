import org.scalatest._

import oxide.Errors._
import oxide.Syntax._
import oxide.TypeChecker

class TypeCheckerTests extends FlatSpec with Matchers {
  "The Oxide type checker" should "type check binding a variable to an allocated primitive" in {
    TypeChecker((), Map(), Map(), Map()).check(
      ELet(QMut, "x", EAlloc(RConcrete(0), EPrim(ENum(5))),
           EPrim(EUnit))
    ) should be (
      TBase(TUnit), Map(RConcrete(0) -> (TBase(Tu32), F1, MNone)), Map("x" -> RConcrete(0))
    )
  }

  it should "type check a single mutable borrow from a region" in {
    TypeChecker((), Map(), Map(), Map()).check(
      ELet(QMut, "x", EAlloc(RConcrete(0), EPrim(ENum(5))),
           ELet(QMut, "y", EBorrow(RConcrete(1), QMut, "x", Seq()),
                EPrim(EUnit)))
    ) should be (
      TBase(TUnit), Map(RConcrete(0) -> (TBase(Tu32), F0, MNone),
                        RConcrete(1) -> (TBase(Tu32), F1, MAlias(RConcrete(0)))),
      Map("x" -> RConcrete(0), "y" -> RConcrete(1))
    )
  }

  it should "not type check borrowing mutably twice from the same region" in {
    a [IllegalBorrow] should be thrownBy {
      TypeChecker((), Map(), Map(), Map()).check(
        ELet(QMut, "x", EAlloc(RConcrete(0), EPrim(ENum(5))),
             ELet(QMut, "y", EBorrow(RConcrete(1), QMut, "x", Seq()),
                  ELet(QMut, "z", EBorrow(RConcrete(2), QMut, "x", Seq()),
                       EPrim(EUnit))))
      )
    }
  }

  it should "type check a mutable borrow from within an aggregate region" in {
    TypeChecker((), Map(), Map(), Map()).check(
      ELet(QMut, "x", EAlloc(RConcrete(0),
                             EProd(Seq(EAlloc(RConcrete(1), EPrim(ENum(5)))))),
           ELet(QMut, "y", EBorrow(RConcrete(2), QMut, "x", Seq(PProj(0))),
                EPrim(EUnit)))
    ) should be (
      TBase(TUnit), Map(RConcrete(0) -> (TProd(Seq(TBase(Tu32))), F1,
                                         MAggregate(Map(PProj(0) -> RConcrete(1)))),
                        RConcrete(1) -> (TBase(Tu32), F0, MNone),
                        RConcrete(2) -> (TBase(Tu32), F1, MAlias(RConcrete(1)))),
      Map("x" -> RConcrete(0), "y" -> RConcrete(2))
    )
  }
}
