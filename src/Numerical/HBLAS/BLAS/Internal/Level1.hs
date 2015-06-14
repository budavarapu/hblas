{-# LANGUAGE BangPatterns , RankNTypes, GADTs, DataKinds #-}

module Numerical.HBLAS.BLAS.Internal.Level1(
  AsumFun
  ,AxpyFun
  ,CopyFun
  ,NoScalarDotFun
  ,ScalarDotFun

  ,asumAbstraction
  ,axpyAbstraction
  ,copyAbstraction
  ,noScalarDotAbstraction
  ,scalarDotAbstraction
) where

import Numerical.HBLAS.Constants
import Numerical.HBLAS.UtilsFFI
import Numerical.HBLAS.BLAS.FFI.Level1
import Numerical.HBLAS.MatrixTypes
import Control.Monad.Primitive
import qualified Data.Vector.Storable.Mutable as SM

type AsumFun el res s m = Int -> MDenseVector s Direct el -> Int -> m res
type AxpyFun el s m = Int -> el -> MDenseVector s Direct el -> Int -> MDenseVector s Direct el -> Int -> m()
type CopyFun el s m = Int -> MDenseVector s Direct el -> Int -> MDenseVector s Direct el -> Int -> m()
type NoScalarDotFun el res s m = Int -> MDenseVector s Direct el -> Int -> MDenseVector s Direct el -> Int -> m res
type ScalarDotFun el res s m = Int -> el -> MDenseVector s Direct el -> Int -> MDenseVector s Direct el -> Int -> m res

isVectorBadWithNIncrement :: Int -> Int -> Int -> Bool
isVectorBadWithNIncrement dim n incx = dim < (1 + (n-1) * incx)

vectorBadInfo :: String -> String -> Int -> Int -> Int -> String
vectorBadInfo funName matName dim n incx = "Function " ++ funName ++ ": " ++ matName ++ " constains too few elements of " ++ show dim ++ " and " ++ show (1 + (n-1) * incx) ++ " elements are needed."

{-# NOINLINE asumAbstraction #-}
asumAbstraction:: (SM.Storable el, PrimMonad m) => String ->
  AsumFunFFI el res -> AsumFunFFI el res ->
  AsumFun el res (PrimState m) m
asumAbstraction asumName asumSafeFFI asumUnsafeFFI = asum
  where
    shouldCallFast :: Int -> Bool
    shouldCallFast n = flopsThreshold >= 2 * (fromIntegral n) -- for complex vector, 2n additions are needed
    asum n (MutableDenseVector _ dim _ buff) incx
      | isVectorBadWithNIncrement dim n incx = error $! vectorBadInfo asumName "source matrix" dim n incx
      | otherwise = unsafeWithPrim buff $ \ptr ->
        do unsafePrimToPrim $! (if shouldCallFast n then asumUnsafeFFI else asumSafeFFI) (fromIntegral n) ptr (fromIntegral incx)

{-# NOINLINE axpyAbstraction #-}
axpyAbstraction :: (SM.Storable el, PrimMonad m) => String ->
  AxpyFunFFI scale el -> AxpyFunFFI scale el -> (el -> (scale -> m()) -> m()) ->
  AxpyFun el (PrimState m) m
axpyAbstraction axpyName axpySafeFFI axpyUnsafeFFI constHandler = axpy
  where
    shouldCallFast :: Int -> Bool
    shouldCallFast n = flopsThreshold >= 2 * (fromIntegral n) -- n for a*x, and n for +y
    axpy n alpha
      (MutableDenseVector _ adim _ abuff) aincx
      (MutableDenseVector _ bdim _ bbuff) bincx
        | isVectorBadWithNIncrement adim n aincx = error $! vectorBadInfo axpyName "first matrix" adim n aincx
        | isVectorBadWithNIncrement bdim n bincx = error $! vectorBadInfo axpyName "second matrix" bdim n bincx
        | otherwise =
          unsafeWithPrim abuff $ \ap ->
          unsafeWithPrim bbuff $ \bp ->
          constHandler alpha $ \alphaPtr ->
            do unsafePrimToPrim $! (if shouldCallFast n then axpyUnsafeFFI else axpySafeFFI) (fromIntegral n) alphaPtr ap (fromIntegral aincx) bp (fromIntegral bincx)

{-# NOINLINE copyAbstraction #-}
copyAbstraction :: (SM.Storable el, PrimMonad m) => String ->
  CopyFunFFI el -> CopyFunFFI el ->
  CopyFun el (PrimState m) m
copyAbstraction copyName copySafeFFI copyUnsafeFFI = copy
  where
    shouldCallFast :: Bool
    shouldCallFast = True -- TODO:(yjj) to confirm no flops are needed in copy
    copy n
      (MutableDenseVector _ adim _ abuff) aincx
      (MutableDenseVector _ bdim _ bbuff) bincx
        | isVectorBadWithNIncrement adim n aincx = error $! vectorBadInfo copyName "first matrix" adim n aincx
        | isVectorBadWithNIncrement bdim n bincx = error $! vectorBadInfo copyName "second matrix" bdim n bincx
        | otherwise = 
          unsafeWithPrim abuff $ \ap ->
          unsafeWithPrim bbuff $ \bp ->
            do unsafePrimToPrim $! (if shouldCallFast then copyUnsafeFFI else copySafeFFI) (fromIntegral n) ap (fromIntegral aincx) bp (fromIntegral bincx)

{-# NOINLINE noScalarDotAbstraction #-}
noScalarDotAbstraction :: (SM.Storable el, PrimMonad m) => String ->
  NoScalarDotFunFFI el res -> NoScalarDotFunFFI el res ->
  NoScalarDotFun el res (PrimState m) m
noScalarDotAbstraction dotName dotSafeFFI dotUnsafeFFI = dot
  where
    shouldCallFast :: Int -> Bool
    shouldCallFast n = flopsThreshold >= fromIntegral n
    dot n
      (MutableDenseVector _ adim _ abuff) aincx
      (MutableDenseVector _ bdim _ bbuff) bincx
        | isVectorBadWithNIncrement adim n aincx = error $! vectorBadInfo dotName "first matrix" adim n aincx
        | isVectorBadWithNIncrement bdim n bincx = error $! vectorBadInfo dotName "second matrix" bdim n bincx
        | otherwise = 
          unsafeWithPrim abuff $ \ap ->
          unsafeWithPrim bbuff $ \bp ->
            do unsafePrimToPrim $! (if shouldCallFast n then dotUnsafeFFI else dotSafeFFI) (fromIntegral n) ap (fromIntegral aincx) bp (fromIntegral bincx)

{-# NOINLINE scalarDotAbstraction #-}
scalarDotAbstraction :: (SM.Storable el, PrimMonad m, Show el) => String ->
  ScalarDotFunFFI el res -> ScalarDotFunFFI el res ->
  ScalarDotFun el res (PrimState m) m
scalarDotAbstraction dotName dotSafeFFI dotUnsafeFFI = dot
  where
    shouldCallFast :: Int -> Bool
    shouldCallFast n = flopsThreshold >= fromIntegral n
    dot n sb
      (MutableDenseVector _ adim _ abuff) aincx
      (MutableDenseVector _ bdim _ bbuff) bincx
        | isVectorBadWithNIncrement adim n aincx = error $! vectorBadInfo dotName "first matrix" adim n aincx
        | isVectorBadWithNIncrement bdim n bincx = error $! vectorBadInfo dotName "second matrix" bdim n bincx
        | otherwise = 
          unsafeWithPrim abuff $ \ap ->
          unsafeWithPrim bbuff $ \bp ->
            do unsafePrimToPrim $! (if shouldCallFast n then dotUnsafeFFI else dotSafeFFI) (fromIntegral n) sb ap (fromIntegral aincx) bp (fromIntegral bincx)
