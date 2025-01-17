package main

import (
	"context"
	"github.com/ethereum/go-ethereum/accounts/abi/bind"
	"github.com/ethereum/go-ethereum/accounts/keystore"
	"github.com/ethereum/go-ethereum/crypto"
	"github.com/ethereum/go-ethereum/ethclient"
	"github.com/joho/godotenv"
	"github.com/koriebruh/Ohara/helper"
	"log"
	"math/big"
	"os"
	"path/filepath"
)

func main() {
	ctx := context.Background()
	cwd, err := os.Getwd()
	helper.IfErrFatal(err, "env not found in workdir")

	envFilePath := filepath.Join(cwd, ".env")
	if err = godotenv.Load(envFilePath); err != nil {
		log.Fatalf("Error loading .env file from path %s: %v", envFilePath, err)
	}
	url := os.Getenv("DEPLOY_URL")
	pass := os.Getenv("PASS_WALLET_OWNER")

	//OPEN ENCRYPTED WALLET
	file, err := os.ReadFile("./UTC--2025-01-14T11-02-41.636529300Z--0d518a4c445bbfad90c8382a051a91087d930253")
	helper.IfErrFatal(err, "not found file wallet")
	decryptKey, err := keystore.DecryptKey(file, pass)
	helper.IfErrFatal(err, "failed decrypt wallet wrong pass")

	pvKey := decryptKey.PrivateKey
	publicKey := decryptKey.PrivateKey.PublicKey
	addr := crypto.PubkeyToAddress(publicKey)

	//PREPARE DEPLOY CONTRACT
	c, err := ethclient.DialContext(ctx, url)
	helper.IfErrFatal(err, "failed connect client")
	defer c.Close()

	chainID, _ := c.ChainID(ctx)
	nonceID, _ := c.PendingNonceAt(ctx, addr)
	baseFee := big.NewInt(20000000)  // Base fee, misalnya 20 Gwei
	tipCap := big.NewInt(1000000000) // Tip fee, 1 Gwei
	gasFeeCap := new(big.Int).Add(baseFee, tipCap)

	opts, err := bind.NewKeyedTransactorWithChainID(pvKey, chainID)
	helper.IfErrFatal(err, "failed to bind")
	opts.Nonce = big.NewInt(int64(nonceID))
	opts.GasLimit = 5000000
	opts.GasFeeCap = gasFeeCap
	opts.GasTipCap = tipCap

	//DEPLOY

}
