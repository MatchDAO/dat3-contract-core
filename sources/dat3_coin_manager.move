module dat3::dat3_coin_manager {
    use std::error;
    use std::signer;
    use std::string::{Self, String, utf8};
    use std::vector;

    use aptos_std::math128;
    use aptos_std::math64;
    use aptos_framework::account::{Self, SignerCapability};
    use aptos_framework::coin::{Self, BurnCapability, FreezeCapability, MintCapability};
    use aptos_framework::timestamp::{Self, now_seconds};
    use aptos_framework::reconfiguration;

    use dat3::dat3_coin::DAT3;
    use dat3::dat3_pool_routel;

    #[test_only]
    use aptos_std::debug;
    #[test_only]
    use aptos_framework::aptos_account::create_account;
    #[test_only]
    use aptos_framework::coin::is_account_registered;
    #[test_only]
    use dat3::dat3_pool;
    #[test_only]
    use dat3::dat3_stake;
    #[test_only]
    use aptos_framework::genesis;


    struct HodeCap has key {
        burnCap: BurnCapability<DAT3>,
        freezeCap: FreezeCapability<DAT3>,
        mintCap: MintCapability<DAT3>,
    }

    /// genesis info
    struct GenesisInfo has key, store {
        /// seconds
        genesis_time: u64,
        epoch: u64,
    }

    //Mint Time
    struct MintTime has key, store {
        /// seconds
        time: u64,
        supplyAmount: u64,
        epoch: u64,
    }

    //hode resource account SignerCapability
    struct SignerCapabilityStore has key, store {
        sinCap: SignerCapability,
    }


    /// 100 million
    const MAX_SUPPLY_AMOUNT: u64 = 5256000 ;
    //365
    const SECONDS_OF_YEAR: u128 = 31536000 ;
    const EPOCH_OF_YEAR: u128 = 4380 ;
    //ONE DAY
    //  const SECONDS_OF_DAY: u64 = 86400 ;
    const TOTAL_EMISSION: u128 = 7200;
    //0.7
    const TALK_EMISSION: u128 = 5040;
    //0.15
    const STAKE_EMISSION: u128 = 1080;
    //0.15
    const INVESTER_EMISSION: u128 = 1080;

    const PERMISSION_DENIED: u64 = 1000;
    const SUPPLY_OUT_OF_RANGE: u64 = 1001;

    const EINSUFFICIENT_BALANCE: u64 = 107u64;
    const NO_USER: u64 = 108u64;
    const NO_TO_USER: u64 = 108u64;
    const NOT_FOUND: u64 = 110u64;
    const ALREADY_EXISTS: u64 = 111u64;
    const OUT_OF_RANGE: u64 = 112;
    const INVALID_ARGUMENT: u64 = 113;
    const ASSERT_MINT_ERR: u64 = 114;

    /********************/
    /* ENTRY FUNCTIONS */
    /********************/
    public entry fun init_dat3_coin(owner: &signer)
    {
        assert!(signer::address_of(owner) == @dat3, error::permission_denied(PERMISSION_DENIED));
        //only once
        assert!(!exists<GenesisInfo>(@dat3), error::already_exists(ALREADY_EXISTS));
        let (burnCap, freezeCap, mintCap) =
            coin::initialize<DAT3>(owner,
                string::utf8(b"DAT3_alpha"),
                string::utf8(b"DAT3_alpha"),
                6u8, true);

        let (resourceSigner, sinCap) = account::create_resource_account(owner, b"dat3");
        move_to(&resourceSigner, HodeCap {
            burnCap, freezeCap, mintCap
        });
        move_to(&resourceSigner, SignerCapabilityStore {
            sinCap
        });
        coin::register<DAT3>(owner);
        move_to(&resourceSigner, MintTime { time: 0, supplyAmount: 0, epoch: 0, });
        let time = timestamp::now_seconds();
        move_to(&resourceSigner,
            GenesisInfo {
                genesis_time: time,
                epoch: 0,
            }
        );
        //Inform Genesis
        dat3::dat3_stake::init(owner, time);
    }

    public entry fun mint_to(_owner: &signer) acquires HodeCap, MintTime, GenesisInfo
    {
        assert!(assert_mint_time(), error::aborted(ASSERT_MINT_ERR));
        //for test
        // if(!assert_mint_time()){
        //     return
        // };
        let last = borrow_global_mut<MintTime>(@dat3_admin);
        if (last.time == 0 || last.time == 1) {
            assert!(signer::address_of(_owner) == @dat3, error::permission_denied(PERMISSION_DENIED));
        };
        let cap = borrow_global<HodeCap>(@dat3_admin);

        let mint_amount = assert_mint_num();
        assert!(mint_amount > 0, error::aborted(ASSERT_MINT_ERR));

        let mint_coins = coin::mint((mint_amount as u64), &cap.mintCap);
        let last = borrow_global_mut<MintTime>(@dat3_admin);
        last.supplyAmount = (mint_amount as u64) + last.supplyAmount;
        last.time = now_seconds();
        last.epoch = reconfiguration::current_epoch();
        //begin distribute reward
        //reward fund
        dat3::dat3_pool::deposit_reward_coin(
            coin::extract(&mut mint_coins, ((mint_amount * TALK_EMISSION / TOTAL_EMISSION) as u64))
        );

        //stake reward fund
        dat3::dat3_stake::mint_pool(
            coin::extract(&mut mint_coins, ((mint_amount * STAKE_EMISSION / TOTAL_EMISSION) as u64))
        );
        //team fund
        coin::deposit(@dat3, mint_coins);
        //distribute reward
        dat3_pool_routel::to_reward();
    }
    /*********************/
    /* PRIVATE FUNCTIONS */
    /*********************/

    //Make sure it's only once a day
    fun assert_mint_time(): bool acquires MintTime
    {
        let last = borrow_global<MintTime>(@dat3_admin);
        //Maximum Mint
        if (last.supplyAmount >= MAX_SUPPLY_AMOUNT * math64::pow(10, (coin::decimals<DAT3>() as u64))) {
            return false
        };
        if (last.epoch == 0) {
            return true
        } else if (reconfiguration::current_epoch() - last.epoch >= 12) {
            //current_epoch - last.epoch =12
            // 0  2  4  6  8  10 12 14 16 18 20  22   0    2   4  6   8   10  12  14  16  18  20  22  0   2  4  6  8  10 12 14 16 18 20 22 0
            // 1  2  3  4  5  6  7  8  9  10  11  12  13  14  15  16  17  18  19  20  21  22  23  24  25  26 27 28 29 30 31 32 33 34 35 36 37 38 39 40
            // 1                                      1                                               1                                    1
            //                                       12                                               12                                   12
            return true
        };
        return false
    }

    //The number of coins that can be mint today
    fun assert_mint_num(): u128 acquires MintTime, GenesisInfo
    {
        let last = borrow_global<MintTime>(@dat3_admin);
        let gen = borrow_global<GenesisInfo>(@dat3_admin);
        //Maximum Mint
        if (last.supplyAmount >= MAX_SUPPLY_AMOUNT * math64::pow(10, (coin::decimals<DAT3>() as u64))) {
            return 0u128
        };
        let now = reconfiguration::current_epoch();
        let year = ((now - gen.epoch) as u128) / EPOCH_OF_YEAR ;
        let m = 1u128;
        let i = 0u128;
        while (i < year) {
            m = m * 2;
            i = i + 1;
        };
        let mint = TOTAL_EMISSION * math128::pow(10, ((coin::decimals<DAT3>()) as u128)) / m  ;
        return mint
    }
    /*********************/
    /* VIEW FUNCTIONS */
    /*********************/
    #[view]
    public fun genesis_info(): (u64, u128, u64) acquires MintTime, GenesisInfo
    {
        let last = borrow_global<MintTime>(@dat3_admin);
        let gen = borrow_global<GenesisInfo>(@dat3_admin);
        let now = timestamp::now_seconds();
        let year = ((now - gen.genesis_time) as u128) / SECONDS_OF_YEAR ;
        let m = 1u128;
        let i = 0u128;
        while (i < year) {
            m = m * 2;
            i = i + 1;
        };
        let mint = TOTAL_EMISSION * (coin::decimals<DAT3>() as u128) / m ;
        (gen.genesis_time, mint, last.time)
    }

    /*********/
    /* TESTS */
    /*********/

    #[test(dat3 = @dat3, _to = @dat3_admin, fw = @aptos_framework)]
    fun mint_test(dat3: &signer, _to: &signer, fw: &signer) acquires MintTime, GenesisInfo, HodeCap
    {
        genesis::setup();
        timestamp::set_time_has_started_for_testing(fw);
        timestamp::update_global_time_for_test(1679899905000000);
        let addr = signer::address_of(dat3);
        create_account(addr);
        init_dat3_coin(dat3);
        dat3_pool::init_pool(dat3);
        dat3_pool_routel::init(dat3);
        let i = 0;//time
        let time = 1679899905000000;
        debug::print(&time);
        // let time=timestamp::update_global_time_for_test(8100000);

        while (i < 8780) {
            time = time + 10000000;
            timestamp::update_global_time_for_test(time);
            reconfiguration::reconfigure_for_test_custom();
            mint_to(dat3);
            debug::print(&coin::balance<DAT3>(@dat3));

            i = i + 1;
        };
        let last = borrow_global_mut<MintTime>(@dat3_admin);
        debug::print(&last.supplyAmount);
    }

    #[test ]
    fun temp_test()
    {
        let ten = 10u64;
        let temp = 3u64;
        debug::print(&((((ten as u128) * 100000) / (temp as u128)) as u64));
    }

    #[test(dat3 = @dat3, to = @dat3_admin, fw = @aptos_framework)]
    fun assert_mint_num_test(dat3: &signer, to: &signer, fw: &signer) acquires MintTime, GenesisInfo
    {
        genesis::setup();
        timestamp::set_time_has_started_for_testing(fw);
        timestamp::update_global_time_for_test(1679899905000000);
        let addr = signer::address_of(dat3);
        let to_addr = signer::address_of(to);
        create_account(addr);
        create_account(to_addr);
        init_dat3_coin(dat3);
        let i = 0;//time
        let time = 1679899905000000;
        debug::print(&time);
        while (i < 21908) {
            time = time + 10000000;
            timestamp::update_global_time_for_test(time);
            reconfiguration::reconfigure_for_test_custom();
            let sss = assert_mint_num();
            if (sss > 0) {
                debug::print(&i);
                debug::print(&sss);
            };
            i = i + 1;
        };
    }

    #[test(dat3 = @dat3, to = @dat3_admin, fw = @aptos_framework)]
    fun assert_mint_time_test(dat3: &signer, to: &signer, fw: &signer) acquires MintTime, GenesisInfo
    {
        genesis::setup();
        timestamp::set_time_has_started_for_testing(fw);
        timestamp::update_global_time_for_test(1679899905000000);
        let addr = signer::address_of(dat3);
        let to_addr = signer::address_of(to);
        create_account(addr);
        create_account(to_addr);
        init_dat3_coin(dat3);
        let i = 0;//time
        let time = 1679899905000000;
        debug::print(&time);
        while (i < 43815) {
            time = time + 10000000;
            timestamp::update_global_time_for_test(time);
            reconfiguration::reconfigure_for_test_custom();
            let sss = assert_mint_time();
            if (sss) {
                let num = assert_mint_num();
                let mint_time = borrow_global_mut<MintTime>(@dat3_admin);

                mint_time.epoch = reconfiguration::current_epoch();
                mint_time.supplyAmount = mint_time.supplyAmount + (num as u64);
                debug::print(&reconfiguration::current_epoch());
                debug::print(&mint_time.supplyAmount);
                debug::print(&num);
            };
            i = i + 1;
        };
    }


    #[test(dat3 = @dat3, to = @dat3_admin, fw = @aptos_framework)]
    fun dat3_stake(dat3: &signer, to: &signer, fw: &signer)
    {
        timestamp::set_time_has_started_for_testing(fw);
        timestamp::update_global_time_for_test(1651255555255555);
        let addr = signer::address_of(dat3);
        let to_addr = signer::address_of(to);
        create_account(addr);
        create_account(to_addr);
        init_dat3_coin(dat3);
        dat3_pool::init_pool(dat3);
        coin::register<DAT3>(dat3);
        debug::print(&is_account_registered<DAT3>(addr));
        // dat3_pool_routel::init(dat3);
        debug::print(&string::utf8(b"begin"));
        debug::print(&coin::balance<DAT3>(addr));
        //  dat3_stake::deposit(dat3, 10000000, 10);
        debug::print(&coin::balance<DAT3>(addr));
        // dat3_stake::withdraw(dat3);
        debug::print(&coin::balance<DAT3>(addr));
        debug::print(&coin::balance<DAT3>(addr));
        let (v1, v2, v3, v4, v5, v6, v7, v8, v9, v10, v11, v12) =
            dat3_stake::apr(10000000000000, 25, false);
        debug::print(&string::utf8(b"begin1111111111111111111111111"));
        debug::print(&v1);
        debug::print(&v2);
        debug::print(&v3);
        debug::print(&v4);
        debug::print(&v5);
        debug::print(&v6);
        debug::print(&v7);
        debug::print(&v8);
        debug::print(&v9);
        debug::print(&v10);
        debug::print(&v11);
        debug::print(&v12);


        //
        // let (v1, v2, v3, v4, v5, v6, v7, v8, v9, v10, v11, v12) =
        //     dat3_stake::your_staking(addr);
        // debug::print(&string::utf8(b"0000000000000000000000000000000000"));
        // debug::print(&v1);
        // debug::print(&v2);
        // debug::print(&v3);
        // debug::print(&v4);
        // debug::print(&v5);
        // debug::print(&v6);
        // debug::print(&v7);
        // debug::print(&v8);
        // debug::print(&v9);
        // debug::print(&v10);
        // debug::print(&v11);
        // debug::print(&v12);
        //
        // dat3_stake::deposit(dat3, 10000000, 10);
        // (v1, v2, v3, v4, v5, v6, v7, v8, v9, v10, v11, v12) =
        //     dat3_stake::your_staking_more(addr, 10000000, 1);
        // debug::print(&string::utf8(b"111111111111111111111111111111111111"));
        // debug::print(&v1);
        // debug::print(&v2);
        // debug::print(&v3);
        // debug::print(&v4);
        // debug::print(&v5);
        // debug::print(&v6);
        // debug::print(&v7);
        // debug::print(&v8);
        // debug::print(&v9);
        // debug::print(&v10);
        // debug::print(&v11);
        // debug::print(&v12);
    }

    #[test(dat3 = @dat3, to = @dat3_admin, fw = @aptos_framework)]
    fun dat3_routel_call_1(dat3: &signer, to: &signer, fw: &signer)
    {
        debug::print(&u64_to_string(6u64));
        debug::print(&intToString(6u64));
        timestamp::set_time_has_started_for_testing(fw);
        timestamp::update_global_time_for_test(1);

        let addr = signer::address_of(dat3);

        let to_addr = signer::address_of(to);
        let _aptos = signer::address_of(fw);
        create_account(addr);
        create_account(to_addr);
        let (burn_cap, mint_cap) = aptos_framework::aptos_coin::initialize_for_test(fw);
        coin::deposit(signer::address_of(dat3), coin::mint(100111000000, &mint_cap));
        coin::deposit(signer::address_of(dat3), coin::mint(101110000000, &mint_cap));

        init_dat3_coin(dat3);
        dat3_pool::init_pool(dat3);
        coin::register<DAT3>(dat3);
        coin::register<0x1::aptos_coin::AptosCoin>(dat3);
        debug::print(&is_account_registered<DAT3>(addr));
        dat3_pool_routel::init(dat3);
        dat3_pool_routel::user_init(dat3, 999, 100);
        dat3_pool_routel::user_init(to, 998, 100);
        // dat3_pool_routel::user_init(to, 998, 100);
        dat3_pool_routel::deposit(dat3, 1000000000);
        debug::print(&(((1000000 as u128) * 500 / 100000)));
        debug::print(&string::utf8(b"00000000000000000000"));
        dat3_pool_routel::call_1(dat3, to_addr) ;
        // dat3_pool_routel::call_1(dat3,to_addr);
        debug::print(&dat3_pool_routel::is_sender(to_addr, addr));
        dat3_pool_routel::sys_call_1(dat3, addr, to_addr, 0);
        // debug::print(&dat3_pool_routel::call_1(to, addr));
        // dat3_pool_routel::call_1(to, addr);
        let (v1, v2, v3, v4, v5, v6, v7, v8, v9, v10) =
            dat3_pool_routel::assets(to_addr);
        debug::print(&string::utf8(b"begin11111"));
        debug::print(&v1);
        debug::print(&v2);
        debug::print(&v3);
        debug::print(&v4);
        debug::print(&v5);
        debug::print(&v6);
        debug::print(&v7);
        debug::print(&v8);
        debug::print(&v9);
        debug::print(&v10);
        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);
        debug::print(&string::utf8(b"begin22222"));
        let (v1, v2, v3, v4, v5, v6) =
            dat3_pool_routel::fid_reward(999);
        debug::print(&v1);
        debug::print(&v2);
        debug::print(&v3);
        debug::print(&v4);
        debug::print(&v5);
        debug::print(&v6);
        debug::print(&string::utf8(b"9999999999888888"));
        let (v1, v2, v3, v4, v5, v6) =
            dat3_pool_routel::fid_reward(998);
        debug::print(&v1);
        debug::print(&v2);
        debug::print(&v3);
        debug::print(&v4);
        debug::print(&v5);
        debug::print(&v6);
        //  dat3_pool_routel::to_reward(dat3);
        // let (v1, v2, v3, v4, v5, v6) = dat3_pool_routel::reward_record(to_addr);
        debug::print(&string::utf8(b"begin3333333333"));

        // debug::print(&v1);
        // debug::print(&v2);
        // debug::print(&v3);
        // debug::print(&v4);
        // debug::print(&v5);
        // debug::print(&v6);
        timestamp::update_global_time_for_test(1100000);
        debug::print(&timestamp::now_seconds());

        timestamp::update_global_time_for_test(8100000);
        dat3_pool_routel::one_minute(dat3, @dat3_routel, 1, ) ;
        dat3_pool_routel::one_minute(dat3, @dat3_routel, 1) ;

        let (v1, v2, v3, v4, v5, v6, v7, v8, v9, v10) =
            dat3_pool_routel::assets(@dat3_routel);
        debug::print(&string::utf8(b"begin11111"));
        debug::print(&v1);
        debug::print(&v2);
        debug::print(&v3);
        debug::print(&v4);
        debug::print(&v5);
        debug::print(&v6);
        debug::print(&v7);
        debug::print(&v8);
        debug::print(&v9);
        debug::print(&v10);
    }

    #[test(dat3 = @dat3, to = @dat3_admin, fw = @aptos_framework)]
    fun dat3_routel_call(dat3: &signer, to: &signer, fw: &signer)
    {
        debug::print(&u64_to_string(6u64));
        debug::print(&intToString(6u64));
        timestamp::set_time_has_started_for_testing(fw);
        timestamp::update_global_time_for_test(1);

        let addr = signer::address_of(dat3);

        let to_addr = signer::address_of(to);
        let _aptos = signer::address_of(fw);
        create_account(addr);
        create_account(to_addr);
        let (burn_cap, mint_cap) = aptos_framework::aptos_coin::initialize_for_test(fw);
        coin::deposit(signer::address_of(dat3), coin::mint(100111000000, &mint_cap));
        coin::deposit(signer::address_of(dat3), coin::mint(101110000000, &mint_cap));

        init_dat3_coin(dat3);
        dat3_pool::init_pool(dat3);
        coin::register<DAT3>(dat3);
        coin::register<0x1::aptos_coin::AptosCoin>(dat3);
        debug::print(&is_account_registered<DAT3>(addr));
        dat3_pool_routel::init(dat3);
        dat3_pool_routel::user_init(dat3, 999, 100);
        // dat3_pool_routel::user_init(to, 998, 100);
        dat3_pool_routel::deposit(dat3, 1000000000);
        debug::print(&string::utf8(b"00000000000000000000"));

        let (v1, v2, v3, v4, v5, v6, v7, v8, v9, v10) =
            dat3_pool_routel::assets(addr);
        debug::print(&string::utf8(b"begin11111"));
        debug::print(&v1);
        debug::print(&v2);
        debug::print(&v3);
        debug::print(&v4);
        debug::print(&v5);
        debug::print(&v6);
        debug::print(&v7);
        debug::print(&v8);
        debug::print(&v9);
        debug::print(&v10);
        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);
        debug::print(&string::utf8(b"begin22222"));
        let (v1, v2, v3, v4, v5, v6) =
            dat3_pool_routel::fid_reward(999);
        debug::print(&v1);
        debug::print(&v2);
        debug::print(&v3);
        debug::print(&v4);
        debug::print(&v5);
        debug::print(&v6);
        let (v1, v2, v3, v4, v5, v6) =
            dat3_pool_routel::fid_reward(998);
        debug::print(&v1);
        debug::print(&v2);
        debug::print(&v3);
        debug::print(&v4);
        debug::print(&v5);
        debug::print(&v6);
        //  dat3_pool_routel::to_reward(dat3);
        // let (v1, v2, v3, v4, v5, v6) = dat3_pool_routel::reward_record(to_addr);
        debug::print(&string::utf8(b"begin3333333333"));

        // debug::print(&v1);
        // debug::print(&v2);
        // debug::print(&v3);
        // debug::print(&v4);
        // debug::print(&v5);
        // debug::print(&v6);
        timestamp::update_global_time_for_test(1100000);
        debug::print(&timestamp::now_seconds());

        timestamp::update_global_time_for_test(8100000);
        dat3_pool_routel::one_minute(dat3, @dat3_routel, 1, ) ;
        dat3_pool_routel::one_minute(dat3, @dat3_routel, 1) ;

        let (v1, v2, v3, v4, v5, v6, v7, v8, v9, v10) =
            dat3_pool_routel::assets(@dat3_routel);
        debug::print(&string::utf8(b"begin11111"));
        debug::print(&v1);
        debug::print(&v2);
        debug::print(&v3);
        debug::print(&v4);
        debug::print(&v5);
        debug::print(&v6);
        debug::print(&v7);
        debug::print(&v8);
        debug::print(&v9);
        debug::print(&v10);
        dat3_pool_routel::one_minute(dat3, to_addr, 1);
        let (v1, v2, v3, v4, v5, v6) =
            dat3_pool_routel::fid_reward(999);
        debug::print(&v1);
        debug::print(&v2);
        debug::print(&v3);
        debug::print(&v4);
        debug::print(&v5);
        debug::print(&v6);
        let (v1, v2, v3, v4, v5, v6) =
            dat3_pool_routel::fid_reward(998);
        debug::print(&v1);
        debug::print(&v2);
        debug::print(&v3);
        debug::print(&v4);
        debug::print(&v5);
        debug::print(&v6);
        let (v1, v2, v3, v4, v5, v6) =
            dat3_pool_routel::fid_reward(999);
        debug::print(&v1);
        debug::print(&v2);
        debug::print(&v3);
        debug::print(&v4);
        debug::print(&v5);
        debug::print(&v6);
        let v1 = dat3_pool_routel::remaining_time(addr);
        debug::print(&string::utf8(b"begin44444444444444"));
        debug::print(&v1);
        timestamp::update_global_time_for_test(18100000);
        //dat3_pool_routel::one_minute(dat3,to_addr);
        timestamp::update_global_time_for_test(28100000);
        //dat3_pool_routel::one_minute(dat3,to_addr);
        let v1 = dat3_pool_routel::remaining_time(addr);
        debug::print(&string::utf8(b"begin44444444444444"));
        debug::print(&v1);


        let (v1, v2, v3, v4, v5, v6, v7) = dat3_pool_routel::reward_record(to_addr);
        debug::print(&string::utf8(b"begin5555555"));
        debug::print(&v1);
        debug::print(&v2);
        debug::print(&v3);
        debug::print(&v4);
        debug::print(&v5);
        debug::print(&v6);
        debug::print(&v7);
        let (v1, v2, v3, v4, v5, v6, v7) = dat3_pool_routel::reward_record(addr);
        debug::print(&string::utf8(b"begin6666666666666666"));
        debug::print(&v1);
        debug::print(&v2);
        debug::print(&v3);
        debug::print(&v4);
        debug::print(&v5);
        debug::print(&v6);
        debug::print(&v7);
    }

    const NUM_VEC: vector<u8> = b"0123456789";

    fun u64_to_string(value: u64): String
    {
        if (value == 0) {
            return utf8(b"0")
        };
        let buffer = vector::empty<u8>();
        while (value != 0) {
            vector::push_back(&mut buffer, ((48 + value % 10) as u8));
            value = value / 10;
        };
        vector::reverse(&mut buffer);
        utf8(buffer)
    }

    fun intToString(_n: u64): String {
        let v = _n;
        let str_b = b"";
        if (v > 0) {
            while (v > 0) {
                let rest = v % 10;
                v = v / 10;
                vector::push_back(&mut str_b, *vector::borrow(&NUM_VEC, rest));
            };
            vector::reverse(&mut str_b);
        } else {
            vector::append(&mut str_b, b"0");
        };
        string::utf8(str_b)
    }

    #[test(dat3 = @dat3)]
    fun get_test_resource_account(dat3: &signer)
    {
        let (_, dat3_admin) =
            account::create_resource_account(dat3, b"dat3");
        let (_, dat3_pool) =
            account::create_resource_account(dat3, b"dat3_pool");
        let (_, dat3_routel) =
            account::create_resource_account(dat3, b"dat3_routel");
        let (_, dat3_stake) =
            account::create_resource_account(dat3, b"dat3_stake");
        let (_, dat3_nft) =
            account::create_resource_account(dat3, b"dat3_nft");

        let sig = account::create_signer_with_capability(&dat3_admin);
        let sig2 = account::create_signer_with_capability(&dat3_pool);
        let sig3 = account::create_signer_with_capability(&dat3_routel);
        let sig4 = account::create_signer_with_capability(&dat3_stake);
        let sig5 = account::create_signer_with_capability(&dat3_nft);
        debug::print(&string::utf8(b"-------------------"));
        debug::print(&signer::address_of(dat3));
        debug::print(&signer::address_of(&sig));
        debug::print(&signer::address_of(&sig2));
        debug::print(&signer::address_of(&sig3));
        debug::print(&signer::address_of(&sig4));
        debug::print(&signer::address_of(&sig5));
    }
}