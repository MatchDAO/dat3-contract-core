module dat3::dat3_stake {
    use std::error;
    use std::signer;
    use std::vector;

    use aptos_std::math128;
    use aptos_framework::coin::{Coin, Self};
    use aptos_framework::timestamp;

    use dat3::dat3_coin::DAT3;
    use dat3::simple_mapv1::{Self, SimpleMapV1};
    use aptos_framework::account::SignerCapability;
    use aptos_framework::account;

    friend dat3::dat3_coin_manager;
    struct SignerCapabilityStore has key, store {
        sinCap: SignerCapability,
    }

    struct UserPosition has key, store {
        amount_staked: u64,
        start_time: u64,
        duration: u64,
        reward: Coin<DAT3>,
        already_reward: u64,
        flexible: bool,
        veDAT3: u64,

    }

    struct PoolInfo has key, store {
        data: SimpleMapV1<address, UserPosition>
    }

    struct Pool has key, store {
        stake: Coin<DAT3>,
        reward: Coin<DAT3>,
        rate_of: u128,
        rate_of_decimal: u128,
        max_lock_time: u64,
    }

    struct GenesisInfo has key, store {
        /// seconds
        genesis_time: u64,
    }

    /********************/
    /*   CONST          */
    /********************/

    /// 100 million
    const MAX_SUPPLY_AMOUNT: u64 = 5256000 ;
    //365
    const SECONDS_OF_YEAR: u128 = 31536000 ;
    //365
    const SECONDS_OF_WEEK: u128 = 604800 ;
    //ONE DAY
    const SECONDS_OF_DAY: u128 = 86400 ;

    const TOTAL_EMISSION: u128 = 7200;
    //7d of seconds
    const ONE_W: u64 = 604800;

    /********************/
    /*   ERROR          */
    /********************/
    const PERMISSION_DENIED: u64 = 1000;
    const INVALID_ARGUMENT: u64 = 105;
    const OUT_OF_RANGE: u64 = 106;
    const EINSUFFICIENT_BALANCE: u64 = 107;
    const NO_USER: u64 = 108;
    const NO_TO_USER: u64 = 109;
    const NOT_FOUND: u64 = 111;
    const ALREADY_EXISTS: u64 = 112;
    const INCENTIVE_POOL_NOT_FOUND: u64 = 400;
    const DEADLINE_ERR: u64 = 401;



    /********************/
    /*   ENTRY FUNCTIONS */
    /********************/

    // Deposit stake coin to the incentive pool to start earning rewards.
    // All pending rewards will be transferred to `sender`.
    public entry fun deposit(sender: &signer, amount: u64, duration: u64)
    acquires Pool, PoolInfo
    {
        let addr = signer::address_of(sender);

        assert!(coin::is_account_registered<DAT3>(addr), error::aborted(INVALID_ARGUMENT));
        assert!(exists<Pool>(@dat3_stake), error::aborted(INCENTIVE_POOL_NOT_FOUND));

        let pool = borrow_global_mut<Pool>(@dat3_stake);
        assert!(duration <= pool.max_lock_time, error::aborted(INVALID_ARGUMENT));
        let pool_info = borrow_global_mut<PoolInfo>(@dat3_stake);
        let stake = coin::withdraw<DAT3>(sender, amount);
        // Deposit staked coin
        coin::merge(&mut pool.stake, stake);
        let flexible = false;
        if (duration == 0) {
            flexible = true;
        };
        // Update UserPosition
        if (!simple_mapv1::contains_key(&pool_info.data, &addr)) {
            simple_mapv1::add(&mut pool_info.data, addr, UserPosition {
                amount_staked: amount,
                start_time: timestamp::now_seconds(),
                duration,
                already_reward: 0u64,
                reward: coin::zero<DAT3>(),
                flexible,
                veDAT3: 0u64
            })
        } else {
            let user = simple_mapv1::borrow_mut(&mut pool_info.data, &addr);
            user.amount_staked = user.amount_staked + amount;
            if (user.duration + duration >= pool.max_lock_time) {
                duration = 52;
            }else {
                duration = user.duration + duration;
            };
            if (duration > 0) {
                flexible = false;
            };
            if(user.start_time==0){
                user.start_time=timestamp::now_seconds();
            };
            user.duration = duration;
            user.flexible = flexible;
        };
    }

    // Withdraw stake coin from the incentive pool.
    // All pending rewards will be transferred to `sender`.
    public entry fun withdraw(sender: &signer) acquires Pool, PoolInfo
    {
        let addr = signer::address_of(sender);
        assert!(coin::is_account_registered<DAT3>(addr), error::aborted(INVALID_ARGUMENT));
        assert!(exists<Pool>(@dat3_stake), error::aborted(INCENTIVE_POOL_NOT_FOUND));


        let pool_info = borrow_global_mut<PoolInfo>(@dat3_stake);
        assert!(simple_mapv1::contains_key(&pool_info.data, &addr), error::not_found(NO_USER));
        let pool = borrow_global_mut<Pool>(@dat3_stake);
        let user = simple_mapv1::borrow_mut(&mut pool_info.data, &addr);
        assert!(user.amount_staked > 0, error::aborted(EINSUFFICIENT_BALANCE));
        coin::deposit(addr, coin::extract(&mut pool.stake, user.amount_staked));
        user.amount_staked = 0;
        user.duration = 0;
        user.start_time = 0;

    }

    //more_stake
    public entry fun more_stake(sender: &signer, amount: u64) acquires Pool, PoolInfo
    {
        let addr = signer::address_of(sender);
        assert!(coin::is_account_registered<DAT3>(addr), error::aborted(NOT_FOUND));
        assert!(exists<Pool>(@dat3_stake), error::aborted(INCENTIVE_POOL_NOT_FOUND));
        let pool_info = borrow_global_mut<PoolInfo>(@dat3_stake);
        // check user
        assert!(simple_mapv1::contains_key(&pool_info.data, &addr), error::aborted(NO_USER));
        let pool = borrow_global_mut<Pool>(@dat3_stake);
        // Deposit staked coin
        let stake = coin::withdraw<DAT3>(sender, amount);
        coin::merge(&mut pool.stake, stake);
        //add user staked
        let user = simple_mapv1::borrow_mut(&mut pool_info.data, &addr);
        if(user.start_time==0){
            user.start_time=timestamp::now_seconds();
        };
        user.amount_staked = user.amount_staked + amount;
    }

    //more_duration
    public entry fun more_duration(sender: &signer, duration: u64) acquires Pool, PoolInfo
    {
        let addr = signer::address_of(sender);
        assert!(coin::is_account_registered<DAT3>(addr), error::permission_denied(INVALID_ARGUMENT));
        assert!(exists<Pool>(@dat3_stake), error::aborted(INCENTIVE_POOL_NOT_FOUND));
        let pool_info = borrow_global_mut<PoolInfo>(@dat3_stake);
        // check user
        assert!(simple_mapv1::contains_key(&pool_info.data, &addr), NO_USER);

        //get max_lock_time
        let pool = borrow_global<Pool>(@dat3_stake);
        //add user duration
        let user = simple_mapv1::borrow_mut(&mut pool_info.data, &addr);
        if ((user.amount_staked + duration) >= pool.max_lock_time) {
            duration = pool.max_lock_time;
        }else {
            duration = user.amount_staked + duration;
        };
        if(duration>0){
            user.flexible=false;
        };
        if(user.start_time==0){
            user.start_time=timestamp::now_seconds();
        };
        user.duration = duration;
    }

    // Claim staking rewards without modifying staking position
    public entry fun claim(sender: &signer) acquires PoolInfo
    {
        let addr = signer::address_of(sender);
        assert!(coin::is_account_registered<DAT3>(addr), error::aborted(INVALID_ARGUMENT));
        assert!(exists<Pool>(@dat3_stake), error::aborted(INCENTIVE_POOL_NOT_FOUND));
        let pool_info = borrow_global_mut<PoolInfo>(@dat3_stake);
        assert!(!simple_mapv1::contains_key(&pool_info.data, &addr), NO_USER);
        let user = simple_mapv1::borrow_mut(&mut pool_info.data, &addr);
        coin::deposit<DAT3>(addr, coin::extract_all(&mut user.reward));
    }

    /*********************/
    /* SYS PRIVATE FUNCTIONS */
    /*********************/
    //init
    public entry fun init(owner: &signer, time: u64)
    {
        let addr = signer::address_of(owner);
        assert!(addr == @dat3, error::permission_denied(PERMISSION_DENIED));
        assert!(!exists<GenesisInfo>(addr), error::already_exists(ALREADY_EXISTS));

        let (resourceSigner, sinCap) = account::create_resource_account(owner, b"dat3_stake");
        move_to(&resourceSigner, SignerCapabilityStore {
            sinCap
        });
        move_to<GenesisInfo>(&resourceSigner, GenesisInfo { genesis_time: time });

        if (!exists<Pool>(addr)) {
            move_to<Pool>(&resourceSigner, Pool {
                rate_of: 3836,
                rate_of_decimal: 10000,
                max_lock_time: 52,
                stake: coin::zero<DAT3>(),
                reward: coin::zero<DAT3>(),
            });
        };
        let s = simple_mapv1::create<address, UserPosition>();
        simple_mapv1::add(&mut s, addr, UserPosition {
            amount_staked: 0,
            start_time: 0,
            duration: 0,
            reward: coin::zero<DAT3>(),
            already_reward: 0u64,
            flexible: false,
            veDAT3: 0u64,
        });
        move_to<PoolInfo>(&resourceSigner, PoolInfo {
            data: s,
        });


    }

    public entry fun set_pool(sender: &signer, rate_of: u128, rate_of_decimal: u128, max_lock_time: u64)
    acquires Pool
    {
        let addr = signer::address_of(sender);
        assert!(addr == @dat3, error::aborted(PERMISSION_DENIED));
        assert!(!exists<Pool>(@dat3_stake), error::aborted(ALREADY_EXISTS));
        let pool = borrow_global_mut<Pool>(@dat3_stake);
        if (rate_of > 0) {
            pool.rate_of = rate_of;
        };
        if (rate_of_decimal > 0) {
            pool.rate_of_decimal = rate_of_decimal;
        };
        if (max_lock_time > 0) {
            pool.max_lock_time = max_lock_time;
        };
    }

    /*********************/
    /* FRIEND FUNCTIONS */
    /*********************/

    public(friend) fun mint_pool(coins: Coin<DAT3>)
    acquires Pool, PoolInfo
    {
        let pool = borrow_global_mut<Pool>(@dat3_stake);
        coin::merge(&mut pool.reward, coins);

        let pool_info = borrow_global_mut<PoolInfo>(@dat3_stake);
        let leng = simple_mapv1::length(&mut pool_info.data);
        let volume = 0u128;
        let volume_staked = 0u128;
        let i = 0;
        let users = vector::empty<address>();
        //Expected a single non-reference type
        let now = timestamp::now_seconds();
        while (i < leng) {
            let (address, user) = simple_mapv1::find_index(&pool_info.data, i);
            //   this is passed
            let passed = ((((now as u128) - (user.start_time as u128)) / SECONDS_OF_WEEK) as u64)  ;
            // check amount_staked,check duration,check
            if (user.amount_staked > 0 && (user.duration > passed || user.flexible)) {
                let temp = 0u128;
                if (!user.flexible) {
                    temp = ((user.duration - passed) as u128);
                };
                volume = volume + ((user.amount_staked as u128) * ((temp * pool.rate_of) + pool.rate_of_decimal));
                volume_staked = volume_staked + (user.amount_staked as u128);
                vector::push_back(&mut users, *address)
            };
            i = i + 1;
        };
        leng = vector::length(&users);
        if (leng > 0) {
            i = 0;

            let reward_val = coin::value<DAT3>(&mut pool.reward)  ;
            while (i < leng) {
                let user_address = vector::borrow(&mut users, i);
                let one_of_user = simple_mapv1::borrow_mut(&mut pool_info.data, user_address);
                let passed = ((((now as u128) - (one_of_user.start_time as u128)) / SECONDS_OF_WEEK) as u64)  ;
                let temp = 0u128;
                if (!one_of_user.flexible) {
                    temp = ((one_of_user.duration - passed) as u128);
                };
                let your_stake_factor = (one_of_user.amount_staked as u128) * ((temp * pool.rate_of) + pool.rate_of_decimal);
                let award = (((reward_val as u128) * your_stake_factor / volume
                ) as u64);
                if (coin::value<DAT3>(&mut pool.reward) > 0) {
                    if (coin::value<DAT3>(&pool.reward) < award) {
                        coin::merge(&mut one_of_user.reward, coin::extract_all(&mut pool.reward))
                    }else {
                        coin::merge(&mut one_of_user.reward, coin::extract(&mut pool.reward, award));
                    };
                    one_of_user.already_reward = one_of_user.already_reward + award;
                    one_of_user.veDAT3 = (your_stake_factor as u64);
                };
                i = i + 1;
            };
        };

    }

    /*********************/
    /* VIEW FUNCTIONS */
    /*********************/
    #[view]
    public fun pool_info(): (u64, u64, u128, u128, u64) acquires Pool
    {
        assert!(exists<Pool>(@dat3_stake), error::aborted(INCENTIVE_POOL_NOT_FOUND));
        let pool = borrow_global<Pool>(@dat3_stake);

        (coin::value<DAT3>(&pool.stake),
            coin::value<DAT3>(&pool.reward),
            pool.rate_of,
            pool.rate_of_decimal,
            pool.max_lock_time)
    }

    #[view]
    public fun apr(staking: u64, duration: u64, flexible: bool)
    : (u64, u64, bool, u64, u64, u64, u128, u128, u128, u128, u128, u128)
    acquires Pool, PoolInfo, GenesisInfo
    {
        assert!(exists<Pool>(@dat3_stake), error::already_exists(ALREADY_EXISTS));

        let addr = @0x1010;

        let current_rewards = 0u64;//done

        let pool = borrow_global<Pool>(@dat3_stake);
        let genesis = borrow_global<GenesisInfo>(@dat3_stake);
        //all staking
        let pool_info = borrow_global_mut<PoolInfo>(@dat3_stake);
        let now = timestamp::now_seconds();
        let start = now - 1;
        let temp = 0u128;
        let passed = ((((now as u128) - (start as u128)) / SECONDS_OF_WEEK) as u64);
        if (duration > 52) {
            duration = 52;
        };
        if (duration > passed) {
            temp = ((duration - passed) as u128);
        };
        //add your stake factor
        let boost = ((temp * pool.rate_of) + pool.rate_of_decimal) ;


        let (total_staking, all_simulate_reward, roi, apr, vedat3, taday_ve)
            = staking_calculator(
            addr,
            staking,
            duration,
            flexible,
            start,
            &pool_info.data,
            now,
            genesis.genesis_time,
            pool.rate_of,
            pool.rate_of_decimal
        );
        (staking, duration, flexible, current_rewards, start, (boost as u64), total_staking, all_simulate_reward, roi, apr, vedat3, taday_ve)
    }

    #[view]
    public fun your_staking(addr: address, )
    : (u64, u64, bool, u64, u64, u64, u128, u128, u128, u128, u128, u128) acquires Pool, PoolInfo, GenesisInfo
    {
        assert!(exists<Pool>(@dat3_stake), error::already_exists(ALREADY_EXISTS));
        let pool = borrow_global<Pool>(@dat3_stake);
        //all staking
        let pool_info = borrow_global_mut<PoolInfo>(@dat3_stake);
        if (!simple_mapv1::contains_key(&pool_info.data, &addr)) {
            return (0u64, 0u64, true, 0u64, 0u64, 0u64, (coin::value(
                &pool.stake
            ) as u128), 0u128, 0u128, 0u128, 0u128, 0u128)
        };
        let your_s = simple_mapv1::borrow(&pool_info.data, &addr);
        let _vedat3 = your_s.veDAT3;

        let pool = borrow_global<Pool>(@dat3_stake);
        let genesis = borrow_global<GenesisInfo>(@dat3_stake);

        let duration = your_s.duration  ;
        let staking = your_s.amount_staked  ;
        let flexible = your_s.flexible;
        let current_rewards = coin::value<DAT3>(&your_s.reward);
        let start = your_s.start_time;

        let now = timestamp::now_seconds();
        let temp = 0u128;
        let passed = ((((now as u128) - (start as u128)) / SECONDS_OF_WEEK) as u64);
        //add your stake factor
        let boost = ((temp * pool.rate_of) + pool.rate_of_decimal) ;
        if ((duration > passed || flexible) && staking > 0 && start > 0) {
            temp = ((duration - passed) as u128);

            //add your stake factor
            let boost = ((temp * pool.rate_of) + pool.rate_of_decimal) ;
            // return  (total_staking, staking, duration, flexible, (taday_r as u64), roi, apr, _vedat3)
            let (total_staking, all_simulate_reward, roi, apr, vedat3, _taday_ve)
                = staking_calculator(
                addr,
                staking,
                duration,
                flexible,
                start,
                &pool_info.data,
                now,
                genesis.genesis_time,
                pool.rate_of,
                pool.rate_of_decimal
            );
            return (staking, duration, flexible, current_rewards, start, (boost as u64), total_staking, all_simulate_reward, roi, apr, vedat3, (_vedat3 as u128))
        };

        return (staking, duration, flexible, current_rewards, start, (boost as u64), 0u128, 0u128, 0u128, 0u128, 0u128, (_vedat3 as u128))
    }

    #[view]
    public fun your_staking_more(addr: address, staking_more: u64, duration_more: u64
    ): (u64, u64, bool, u64, u64, u64, u128, u128, u128, u128, u128, u128)
    acquires Pool, PoolInfo, GenesisInfo
    {
        assert!(exists<Pool>(@dat3_stake), error::already_exists(ALREADY_EXISTS));
        let pool = borrow_global<Pool>(@dat3_stake);
        let pool_info = borrow_global_mut<PoolInfo>(@dat3_stake);
        if (!simple_mapv1::contains_key(&pool_info.data, &addr)) {
            return (0u64, 0u64, true, 0u64, 0u64, 0u64, (coin::value(
                &pool.stake
            ) as u128), 0u128, 0u128, 0u128, 0u128, 0u128)
        };
        let vedat3 = 0u128;


        let genesis = borrow_global<GenesisInfo>(@dat3_stake);
        //all staking

        let your_s = simple_mapv1::borrow(&pool_info.data, &addr);
        let duration = your_s.duration + duration_more;
        let staking = your_s.amount_staked + staking_more;
        let flexible = your_s.flexible;
        let current_rewards = coin::value<DAT3>(&your_s.reward);
        let start = your_s.start_time;

        let now = timestamp::now_seconds();
        let temp = 0u128;
        let passed = ((((now as u128) - (start as u128)) / SECONDS_OF_WEEK) as u64);
        if (duration > passed) {
            temp = ((duration - passed) as u128);
        };
        //add your stake factor
        let boost = ((temp * pool.rate_of) + pool.rate_of_decimal) ;


        let (total_staking, all_simulate_reward, remaining_time_roi, apr, remaining_time_vedat3, _taday_ve)
            = staking_calculator(
            addr,
            staking,
            duration,
            flexible,
            start,
            &pool_info.data,
            now,
            genesis.genesis_time,
            pool.rate_of,
            pool.rate_of_decimal
        );
        (staking, duration, flexible, current_rewards, start, (boost as u64), total_staking, all_simulate_reward, remaining_time_roi, apr, (remaining_time_vedat3 + vedat3), _taday_ve)
    }

    /*********************/
    /* PRIVATE FUNCTIONS */
    /*********************/

    fun staking_calculator(
        addr: address,
        staking: u64,
        duration: u64,
        flexible: bool,
        start: u64,
        data: &SimpleMapV1<address, UserPosition>,
        now: u64,
        genesis_time: u64,
        rate_of: u128,
        rate_of_decimal: u128,
    )
    : (u128, u128, u128, u128, u128, u128)
    {
        //(total_staking, staking, duration, flexible, all_simulate_reward, roi, vedat3, (apr as u64))
        let total_staking = (staking as u128);
        let _vedat3 = 0u128;
        let time = (now as u128) + 1;
        let all_simulate_reward = 0u128;

        let users = vector::empty<address>();
        //index
        let i = 0u64;
        let leng = simple_mapv1::length(data);

        let today_volume = 0u128;
        while (i < leng) {
            let (address, user) = simple_mapv1::find_index(data, i);
            //   this is passed
            let passed = ((((now as u128) - (user.start_time as u128)) / SECONDS_OF_WEEK) as u64)  ;
            // check amount_staked,check duration ,check
            if (user.amount_staked > 0 && (user.duration > passed || user.flexible) && address != &addr) {
                //All users who are staking
                total_staking = total_staking + (user.amount_staked as u128);
                let temp_user_passed = (((time - (user.start_time as u128)) / SECONDS_OF_WEEK) as u64);
                if (((user.duration > temp_user_passed) || user.flexible) && *address != addr) {
                    let temp = 0u128;
                    if (!user.flexible) {
                        temp = ((user.duration - temp_user_passed) as u128);
                    };
                    today_volume = today_volume + ((user.amount_staked as u128) * (temp * rate_of + rate_of_decimal));
                };
                vector::push_back(&mut users, *address)
            };
            i = i + 1;
        };
        let today_mint = simulate_mint(genesis_time, (time as u64));
        let my_today = 0u128;
        let passed = ((((now - start) as u128) / SECONDS_OF_WEEK) as u64);
        //current user expiration date
        if (duration > passed || flexible) {
            let temp = 0u128;
            if (! flexible) {
                temp = ((duration - passed) as u128);
            };
            my_today = (staking as u128) * ((temp * rate_of) + rate_of_decimal) ;
        };


        if (flexible) {
            if (simple_mapv1::contains_key(data, &addr)) {
                let you_user = simple_mapv1::borrow(data, &addr);
                //Represents that there are currently staking
                if (you_user.already_reward > 0 && you_user.start_time > 0 && (((now - you_user.start_time) as u128) / SECONDS_OF_DAY) > 0) {
                    let actually_day = ((now - you_user.start_time) as u128) / SECONDS_OF_DAY   ;
                    let apr = (you_user.already_reward as u128) * 365 * 100000000 / (staking as u128) / actually_day   ;
                    // let
                    let roi = (you_user.already_reward as u128) * 100000000 / (staking as u128)  ;

                    _vedat3 = my_today  ;
                    let taday_r = today_mint * my_today / (today_volume + my_today);
                    return (total_staking, taday_r, roi, apr, _vedat3, my_today)

                    //A trailing ';' in an expression block implicitly adds a '()' value after the semicolon. That '()' value will not be reachable
                    //     Any code after this expression will not be reached
                };
            };
            //   staking * y''      y''= (week*0.3836)+1
            let taday_r = today_mint * my_today / (today_volume + my_today);
            let apr = taday_r * 365 * 100000000 / (staking as u128)  / math128::pow(10, (coin::decimals<DAT3>() as u128))  ;
            let roi = (taday_r) * 100000000 / (staking as u128)  ;

            _vedat3 = my_today  ;
            return (total_staking, taday_r, roi, apr, _vedat3, my_today)
        };

        //A trailing ';' in an expression block implicitly adds a '()' value after the semicolon. That '()' value will not be reachable
        //      Any code after this expression will not be reached
        //


        i = 0;
        let maximum = duration * 7 + 1;
        let passed = (((time - (start as u128)) / SECONDS_OF_WEEK) as u64);
        if (duration > passed) {
            maximum = (duration - passed) * 7 + 1
        };

        //Calculate the daily
        while (i < maximum) {
            leng = vector::length(&users);
            let j = 0u64;
            //simulate mint
            let mint = simulate_mint(genesis_time, (time as u64)) ;
            let _volume = 0u128;
            let passed = (((time - (start as u128)) / SECONDS_OF_WEEK) as u64);
            //current user expiration date
            if (duration > passed) {
                let temp = ((duration - passed) as u128);

                //add your stake factor
                let your_stake_factor = (staking as u128) * ((temp * rate_of) + rate_of_decimal) ;
                //reset daily stake factor
                _volume = your_stake_factor;
                if (leng > 0) {
                    while (j < leng) {
                        let add_j = vector::borrow(&users, j);
                        let temp_user = simple_mapv1::borrow(data, add_j);
                        // duration
                        let temp_user_passed = (((time - (temp_user.start_time as u128)) / SECONDS_OF_WEEK) as u64);
                        if (((temp_user.duration > temp_user_passed) || temp_user.flexible) && *add_j != addr) {
                            let temp = 0u128;
                            if (!temp_user.flexible) {
                                temp = ((temp_user.duration - temp_user_passed) as u128);
                            };
                            _volume = _volume + ((temp_user.amount_staked as u128) * (temp * rate_of + rate_of_decimal));
                        }else {
                            vector::swap_remove(&mut users, j)  ;
                            if (j > 1) {
                                j = j - 1;
                            };
                            if ((leng - j) > 1) {
                                leng = leng - 1;
                            };
                        };
                        j = j + 1;
                    };
                };
                all_simulate_reward = all_simulate_reward + mint * your_stake_factor / _volume;
                _vedat3 = _vedat3 + your_stake_factor   ;
            };

            if ((maximum - i) != 1) {
                time = time + SECONDS_OF_DAY;
            };

            i = i + 1;
        };

        let _apr = all_simulate_reward * 100000000 * 364 / ((time - (start as u128)) / SECONDS_OF_DAY) / math128::pow(10, (coin::decimals<DAT3>() as u128))   ;

        let roi = all_simulate_reward * 100000000 / (staking as u128)   ;
        return (total_staking, all_simulate_reward, roi, _apr, _vedat3, my_today)
    }


    fun assert_mint_num(): u128 acquires GenesisInfo
    {
        let gen = borrow_global<GenesisInfo>(@dat3_stake);
        let now = timestamp::now_seconds();
        let year = ((now - gen.genesis_time) as u128) / SECONDS_OF_YEAR ;
        let m = 1u128;
        let i = 0u128;
        while (i < year) {
            m = m * 2;
            i = i + 1;
        };
        let mint = TOTAL_EMISSION / m  ;
        return mint * math128::pow(10, (coin::decimals<DAT3>() as u128))
    }

    fun simulate_mint(genesis_time: u64, now: u64): u128
    {
        let year = ((now - genesis_time) as u128) / SECONDS_OF_YEAR ;
        let m = 1u128;
        let i = 0u128;
        while (i < year) {
            m = m * 2;
            i = i + 1;
        };
        let mint = TOTAL_EMISSION / m / 10  ;
        return mint * math128::pow(10, (coin::decimals<DAT3>() as u128))
        // return mint
    }
}