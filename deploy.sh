#!/bin/bash
DAT3='0xeaca9a4b2c3e5a305099b8f68d90587e7f965e2e1f4b7505368872644ef95746'
PROFILE="test1"
DAT3_PATH=`pwd `

echo "dat3:' $DAT3'"
echo "aptos move compile -->  $DAT3_PATH --bytecode-version 6 "
echo `aptos move compile --save-metadata --package-dir  $DAT3_PATH --bytecode-version 6`
echo""
sleep 5
echo "aptos move publish --> $DAT3_PATH --bytecode-version 6 "
echo `aptos move publish --profile $PROFILE --assume-yes --package-dir  $DAT3_PATH --bytecode-version 6 `
echo""

sleep 3
echo " dat3_pool::init_pool "
echo `aptos move run --profile $PROFILE  --assume-yes --function-id $DAT3::dat3_pool::init_pool `
echo""
sleep 2
echo " dat3_pool_routel::init"
echo `aptos move run --profile $PROFILE  --assume-yes --function-id $DAT3::dat3_pool_routel::init`
echo""
sleep 2