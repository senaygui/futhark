{-# LANGUAGE FlexibleContexts, FlexibleInstances, MultiParamTypeClasses, GeneralizedNewtypeDeriving #-}
module L0C.Tools
  ( letSubExp
  , letSubExps
  , letExp
  , letExps
  , letTupExp

  , newVar

  , eIf
  , eBinOp
  , eIndex
  , eCopy
  , eDoLoop
  , eTupLit

  , MonadBinder(..)
  , Binding(..)
  , insertBindings
  , insertBindings'
  , letBind
  , letWithBind
  , loopBind
  -- * A concrete @Binder@ monad.
  , Binder
  , runBinder
  , runBinderWithNameSource
  -- * Writer convenience interface
  , addBindingWriter
  , collectBindingsWriter
  )
where

import qualified Data.DList as DL
import Data.Loc
import Control.Applicative
import Control.Monad.Writer
import Control.Monad.State

import L0C.InternalRep
import L0C.InternalRep.MonadFreshNames

letSubExp :: MonadBinder m =>
             String -> Exp -> m SubExp
letSubExp _ (SubExp se) = return se
letSubExp desc e =
  case typeOf e of
    [_] -> Var <$> letExp desc e
    _   -> fail $ "letSubExp: tuple-typed expression given for " ++ desc ++ ":\n" ++ ppExp e

letExp :: MonadBinder m =>
          String -> Exp -> m Ident
letExp _ (SubExp (Var v)) = return v
letExp desc e =
  case typeOf e of
    [t] -> do v <- fst <$> newVar (srclocOf e) desc t
              letBind [v] e
              return v
    _   -> fail $ "letExp: tuple-typed expression given:\n" ++ ppExp e

letSubExps :: MonadBinder m =>
              String -> [Exp] -> m [SubExp]
letSubExps desc = mapM $ letSubExp desc

letExps :: MonadBinder m =>
           String -> [Exp] -> m [Ident]
letExps desc = mapM $ letExp desc

letTupExp :: MonadBinder m => String -> Exp -> m [Ident]
letTupExp name e = do
  let ts  = typeOf e
      loc = srclocOf e
  names <- mapM (liftM fst . newVar loc name) ts
  letBind names e
  return names

newVar :: MonadFreshNames VName m =>
          SrcLoc -> String -> Type -> m (Ident, SubExp)
newVar loc name tp = do
  x <- newVName name
  return (Ident x tp loc, Var $ Ident x tp loc)

eIf :: MonadBinder m =>
       m Exp -> m Exp -> m Exp -> [Type] -> SrcLoc -> m Exp
eIf ce te fe ts loc = do
  ce' <- letSubExp "cond" =<< ce
  te' <- insertBindings te
  fe' <- insertBindings fe
  return $ If ce' te' fe' ts loc

eBinOp :: MonadBinder m =>
          BinOp -> m Exp -> m Exp -> Type -> SrcLoc -> m Exp
eBinOp op x y t loc = do
  x' <- letSubExp "x" =<< x
  y' <- letSubExp "y" =<< y
  return $ BinOp op x' y' t loc

eIndex :: MonadBinder m =>
          Certificates -> Ident -> Maybe Certificates -> [m Exp] -> SrcLoc
       -> m Exp
eIndex cs a idxcs idxs loc = do
  idxs' <- letSubExps "i" =<< sequence idxs
  return $ Index cs a idxcs idxs' loc

eCopy :: MonadBinder m =>
         m Exp -> m Exp
eCopy e = do e' <- letSubExp "copy_arg" =<< e
             return $ Copy e' $ srclocOf e'

eDoLoop :: MonadBinder m =>
           [(Ident,m Exp)] -> Ident -> m Exp -> m Exp -> m Exp -> SrcLoc -> m Exp
eDoLoop pat i boundexp loopbody body loc = do
  mergeexps' <- letSubExps "merge_init" =<< sequence mergeexps
  boundexp' <- letSubExp "bound" =<< boundexp
  loopbody' <- loopbody
  body' <- body
  return $ DoLoop (zip mergepat mergeexps') i boundexp' loopbody' body' loc
  where (mergepat, mergeexps) = unzip pat

eTupLit :: MonadBinder m =>
           [m Exp] -> SrcLoc -> m Exp
eTupLit es loc = do
  es' <- letSubExps "tuplit_elems" =<< sequence es
  return $ TupLit es' loc

data Binding = LoopBind [(Ident, SubExp)] Ident SubExp Exp
             | LetBind [Ident] Exp
             | LetWithBind Certificates Ident Ident (Maybe Certificates) [SubExp] SubExp
               deriving (Show, Eq)

class (MonadFreshNames VName m, Applicative m, Monad m) => MonadBinder m where
  addBinding      :: Binding -> m ()
  collectBindings :: m a -> m (a, [Binding])

letBind :: MonadBinder m => [Ident] -> Exp -> m ()
letBind pat e =
  addBinding $ LetBind pat e

letWithBind :: MonadBinder m =>
               Certificates -> Ident -> Ident -> Maybe Certificates -> [SubExp] -> SubExp -> m ()
letWithBind cs dest src idxcs idxs ve =
  addBinding $ LetWithBind cs dest src idxcs idxs ve

loopBind :: MonadBinder m => [(Ident, SubExp)] -> Ident -> SubExp -> Exp -> m ()
loopBind pat i bound loopbody =
  addBinding $ LoopBind pat i bound loopbody

insertBindings :: MonadBinder m => m Exp -> m Exp
insertBindings m = do
  (e,bnds) <- collectBindings m
  return $ insertBindings' e bnds

insertBindings' :: Exp -> [Binding] -> Exp
insertBindings' = foldr bind
  where bind (LoopBind pat i bound loopbody) e =
          DoLoop pat i bound loopbody e $ srclocOf e
        bind (LetBind pat pate) e =
          LetPat pat pate e $ srclocOf e
        bind (LetWithBind cs dest src idxcs idxs ve) e =
          LetWith cs dest src idxcs idxs ve e $ srclocOf e

addBindingWriter :: (MonadFreshNames VName m, Applicative m, MonadWriter (DL.DList Binding) m) =>
                    Binding -> m ()
addBindingWriter = tell . DL.singleton

collectBindingsWriter :: (MonadFreshNames VName m, Applicative m, MonadWriter (DL.DList Binding) m) =>
                         m a -> m (a, [Binding])
collectBindingsWriter m = pass $ do
                            (x, bnds) <- listen m
                            return ((x, DL.toList bnds), const DL.empty)

newtype Binder a = TransformM (WriterT (DL.DList Binding) (State VNameSource) a)
  deriving (Functor, Monad, Applicative,
            MonadWriter (DL.DList Binding), MonadState VNameSource)

instance MonadFreshNames (ID Name) Binder where
  getNameSource = get
  putNameSource = put

instance MonadBinder Binder where
  addBinding      = addBindingWriter
  collectBindings = collectBindingsWriter

runBinder :: MonadFreshNames (ID Name) m => Binder Exp -> m Exp
runBinder m = do
  src <- getNameSource
  let (e,src') = runBinderWithNameSource m src
  putNameSource src'
  return e

runBinderWithNameSource :: Binder Exp -> VNameSource -> (Exp, VNameSource)
runBinderWithNameSource (TransformM m) src =
  let ((e,bnds),src') = runState (runWriterT m) src
  in (insertBindings' e $ DL.toList bnds, src')