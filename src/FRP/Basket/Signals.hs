{-# LANGUAGE TypeOperators, DataKinds, 
             ScopedTypeVariables, TypeFamilies, FlexibleContexts,
             FlexibleInstances, UndecidableInstances #-}

module FRP.Basket.Signals where

import Prelude hiding ((.), const)

import Control.Applicative
import Control.Category
import Control.Arrow
import Data.Monoid hiding ((<>))
import Data.Semigroup
--import FRP.Basket.Aux.HList
import Data.HList 

type Time = Double

newtype Signal s a b = Signal {
                           runSignal :: Time -> HList s -> a -> (b, HList s)
                       }


mkSignal :: (Time -> s -> a -> (b, s)) -> Signal '[s] a b
mkSignal f = Signal $ \t st a -> case st of
                                   (HCons s _) -> let (b, s') = f t s a in (b, HCons s' HNil)

-- this is the same thing as arr, but since I dont know if I'm keeping arrow instances this is here
liftS :: (a -> b) -> Signal '[] a b
liftS f = Signal $ \_ s a -> (f a, s)

-- Pronounced 'weave', this function composes Signals of differing states 
infixr #>
(#>) :: forall s s' ss a b c n. (HSplitAt n ss s s', ss ~ HAppendListR s (HAppendListR s' '[]), 
                                HAppendFD s' '[] s', HAppendFD s s' ss) => 
       Signal s  a b -> Signal s' b c -> Signal ss a c
(Signal f) #> (Signal g) = Signal h where
  splitIndex = Proxy :: Proxy n
  h :: Time -> HList ss -> a -> (c, HList ss)
  h t wstate a = (c, hConcat $ hBuild fState' gState')
    where
      fState, fState' :: HList s
      gState, gState' :: HList s'
      (fState, gState) = hSplitAt splitIndex wstate 
      (b, fState')     = f t fState a 
      (c, gState')     = g t gState b 
                                       

-- need to do these proofs
instance Functor (Signal s a) where
  fmap f (Signal g) = Signal $ \t s a -> let (b, s') = g t s a in (f b, s')


instance Applicative (Signal s a) where
  pure a = Signal $ \_ s _ -> (a, s)
  (Signal f) <*> (Signal g) = Signal $ \t s a -> let (b, s' ) = g t s a 
                                                     (h, s'') = f t s' a in (h b, s'')

instance Monad (Signal s a) where
  return = pure
  (Signal f) >>= g = Signal $ \t s a -> 
                                let (b, s') = f t s a 
                                in runSignal (g b) t s' a

instance Semigroup (Signal s a a) where
  (Signal f) <> (Signal g) = Signal $ \t s a -> let (a' , s') = f t s a in g t s' a'   

instance Category (Signal s) where
  id = Signal $ \_ s a -> (a, s)
  (Signal f) . (Signal g) = Signal $ \t s a -> let (b, s') = g t s a in f t s' b

-- Just like (->), Signal only forms a monoid in Signal s a a..
instance Monoid (Signal s a a) where
  mempty = Signal $ \_ s a -> (a, s)
  mappend = (<>)


-- Maybe a little dissapointing that this needs to be constrained this way, but otherwise
-- the final state is not clear.  
instance Monoid (HList s) => Arrow (Signal s) where
  arr f = Signal $ \_ s a -> (f a, s)
  first (Signal f) = Signal $ \t s (a, c) -> let (b, s') = f t s a in ((b, c), s')
  second (Signal f) = Signal $ \t s (c, a) -> let (b, s') = f t s a in ((c, b), s')
  (Signal f) *** (Signal g) = Signal $ \t s (a, c) -> let (b, s' ) = f t s a 
                                                          (d, s'') = g t s c in ((b, d), s' `mappend` s'') -- which s to use ?
  (Signal f) &&& (Signal g) = Signal $ \t s a -> let (b, s') = f t s a 
                                                     (d, s'') = g t s a in ((b, d), s' `mappend` s'') -- which s to use ?

instance Monoid (HList s) => ArrowChoice (Signal s) where
  left (Signal f) = Signal $ \t s e -> case e of
                                         Left b -> let (c, s') = f t s b in (Left c, s')
                                         Right d -> (Right d, s)
  right (Signal f) = Signal $ \t s e -> case e of
                                         Left b -> (Left b, s)
                                         Right d -> let (b, s') = f t s d in (Right b, s')


instance Monoid (HList s) => ArrowApply (Signal s) where
  app = Signal $ \t s (sf, b) -> runSignal sf t s b

instance Monoid (HList s) => ArrowLoop (Signal s) where
  loop (Signal f) = Signal $ \t s a -> let ((b, d), s') = f t s (a, d) in (b, s')
