> -- | Module:    Control.Quiver
> -- Description: Core Quiver definitions
> -- Copyright:   © 2015 Patryk Zadarnowski <pat@jantar.org>
> -- License:     BSD3
> -- Maintainer:  pat@jantar.org
> -- Stability:   experimental
> -- Portability: portable
> --
> -- This module provides the core types and combinators
> -- of the Quiver stream processing library.

> {-# LANGUAGE RankNTypes, TupleSections #-}

> module Control.Quiver (
>   -- Imported from @Control.Quiver.Internal@:
>   P, Consumer, Producer, Effect,
>   consume, produce, enclose, deliver,
>   decouple, deplete,
>   -- Defined below:
>   fetch, fetch',
>   emit, emit', emit_,
>   liftP,
>   runEffect,
>   (>>->), (>->>),
> ) where

> import Control.Quiver.Internal

> infixl 0 >>->, >->>

> -- | @fetch x@ represents a singleton stream processor that
> --   sends the request value @x@ upstream and delivers the
> --   next input value received, or @Nothing@ if the upstream
> --   processor has been depleted.

> fetch :: a' -> P a' a b' b f (Maybe a)
> fetch x = consume x (deliver . Just) (deliver Nothing)

> -- | @fetch' x q@ represents a singleton stream processor that
> --   sends the request value @x@ upstream and delivers the next
> --   input value received, or, if the upstream processor has
> --   been depleted, continues with the decoupled processor @q@.

> fetch' :: a' -> Producer b' b f a -> P a' a b' b f a
> fetch' x q = consume x deliver q

> -- | @emit y@ represents a singleton stream processor that
> --   produces a single output value @y@ and delivers the
> --   response received from the downstream processor, or
> --   @Nothing@ if the downstream processor has been decoupled.

> emit :: b -> P a' a b' b f (Maybe b')
> emit y = produce y (deliver . Just) (deliver Nothing)

> -- | @emit' y q@ represents a singleton stream processor that
> --   produces a single output value @y@ and delivers the
> --   response received from the downstream processor, or,
> --   if the downstream processor has been decoupled, continues
> --   with the depleted processor @q@.

> emit' :: b -> Consumer a' a f b' -> P a' a b' b f b'
> emit' y q = produce y deliver q

> -- | @emit' y q@ represents a singleton stream processor that
> --   produces a single output value @y@, ignoring any response
> --   received from the downstream processor.

> emit_ :: b -> P a' a b' b f ()
> emit_ y = produce y (deliver . const ()) (deliver ())

> -- | @liftP@ lifts the value of a base functor into a stream processor.

> liftP :: Functor f => f r -> P a' a b' b f r
> liftP = enclose . fmap deliver

> -- | Evaluates an /effect/, i.e., a processor that is both detached
> --   and depleted and hence neither consumes nor produces any input,
> --   returning its delivered value. The base functor must be a monad.

> runEffect :: Monad f => Effect f r -> f r
> runEffect p = loop p
>  where
>   loop (Consume _ _ q) = loop q
>   loop (Produce _ _ q) = loop q
>   loop (Enclose f)     = f >>= loop
>   loop (Deliver r)     = return r

> -- | The @>>->@ represents a push-based composition of stream processor.
> --   @p1 >>-> p2@ represents a stream processor that forwards the output
> --   of @p1@ to @p2@, delivering the result of both processors.
> --   The new processor is /driven/ by @p2@, so, if the base functor
> --   represents a non-commutative monad, any effects of @p2@ will be
> --   observed before those of @p1@.

> (>>->) :: Functor f => P a' a b' b f r1 -> P b' b c' c f r2 -> P a' a c' c f (r1, r2)
> (Consume x1 k1 q1) >>-> p2 = consume x1 ((>>-> p2) . k1) (q1 >>-> p2)
> (Produce y1 k1 q1) >>-> p2 = loop p2
>  where
>   loop  (Consume x2 k2  _) = k1 x2 >>-> k2 y1
>   loop  (Produce y2 k2 q2) = produce y2 (loop . k2) (loop' q2)
>   loop  (Enclose f2)       = enclose (fmap loop f2)
>   loop  (Deliver r2)       = fmap (, r2) q1
>   loop' (Consume x2 k2  _) = k1 x2 >>-> k2 y1
>   loop' (Produce  _  _ q2) = loop' q2
>   loop' (Enclose f2)       = enclose (fmap loop' f2)
>   loop' (Deliver r2)       = fmap (, r2) q1
> (Enclose f1) >>-> p2 = enclose (fmap (>>-> p2) f1)
> (Deliver r1) >>-> p2 = fmap (r1 ,) (decouple p2)

> -- | The @>->>@ represents a pull-based composition of stream processor.
> --   @p1 >->> p2@ represents a stream processor that forwards the output
> --   of @p1@ to @p2@, delivering the result of both processors.
> --   The new processor is /driven/ by @p1@, so, if the base functor
> --   represents a non-commutative monad, any effects of @p1@ will be
> --   observed before those of @p2@.

> (>->>) :: Functor f => P a' a b' b f r1 -> P b' b c' c f r2 -> P a' a c' c f (r1, r2)
> p1 >->> (Consume x2 k2 q2) = loop p1
>  where
>   loop  (Consume x1 k1 q1) = consume x1 (loop . k1) (loop' q1)
>   loop  (Produce y1 k1  _) = k1 x2 >->> k2 y1
>   loop  (Enclose f1)       = enclose (fmap loop f1)
>   loop  (Deliver r1)       = fmap (r1 ,) q2
>   loop' (Consume  _  _ q1) = loop' q1
>   loop' (Produce y1 k1  _) = k1 x2 >->> k2 y1
>   loop' (Enclose f1)       = enclose (fmap loop' f1)
>   loop' (Deliver r1)       = fmap (r1 ,) q2
> p1 >->> (Produce y2 k2 q2) = produce y2 ((p1 >->>) . k2) (p1 >->> q2)
> p1 >->> (Enclose f2)       = enclose (fmap (p1 >->>) f2)
> p1 >->> (Deliver r2)       = fmap (, r2) (deplete p1)
