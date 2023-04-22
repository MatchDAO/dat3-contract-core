module dat3::reward {
    use std::error;
    use std::signer;
    use std::vector;

    use aptos_framework::account::{Self, SignerCapability};
    use aptos_framework::aptos_account::create_account;
    use aptos_framework::coin::{Self, Coin};
    use aptos_framework::timestamp;

    use dat3_owner::invitation_reward;

    use dat3::dat3_coin::DAT3;
    use dat3::pool;
    use dat3::simple_mapv1::{Self, SimpleMapV1};
    use dat3::smart_tablev1::{Self, SmartTablev1};



    friend dat3::interface;

    struct UsersReward has key, store {
        data: SmartTablev1<address, Reward>,
    }


    struct SignerCapabilityStore has key, store {
        sinCap: SignerCapability,
    }

    struct Reward has key, store {
        uid: u64,
        fid: u64,
        //call fee
        mFee: u64,
        //apt
        reward: u64,
        reward_claimed: u64,
        //dat3
        reward_dat3: u64,
        reward_dat3_claimed: u64,
        //talk freeze apt in pool
        taday_spend: u64,
        total_spend: u64,
        total_earn: u64,
        taday_earn: SimpleMapV1<u64, u64>,
        every_dat3_reward: vector<u64>,
        every_dat3_reward_time: vector<u64>,
    }


    struct FeeStore has key, store {
        invite_reward_fee_den: u128,
        invite_reward_fee_num: u128,
        chatFee: u64,
        mFee: SimpleMapV1<u64, u64>,
    }

    struct AdminStore has key, store {
        admin: address,
    }

    //half of the day
    const SECONDS_OF_12HOUR: u64 = 43200 ;
    const SECONDS_OF_DAY: u128 = 86400 ;

    const PERMISSION_DENIED: u64 = 1000;

    const INVALID_ARGUMENT: u64 = 105;
    const OUT_OF_RANGE: u64 = 106;
    const EINSUFFICIENT_BALANCE: u64 = 107;
    const NO_USER: u64 = 108;
    const NO_TO_USER: u64 = 109;
    const NO_RECEIVER_USER: u64 = 110;
    const NOT_FOUND: u64 = 111;
    const ALREADY_EXISTS: u64 = 112;

    const ALREADY_HAS_OPEN_SESSION: u64 = 300;
    const WHO_HAS_ALREADY_JOINED: u64 = 301;
    const YOU_HAS_ALREADY_JOINED: u64 = 302;
    const INVALID_RECEIVER: u64 = 303;
    const INVALID_REQUESTER: u64 = 304;
    const INVALID_ROOM_STATE: u64 = 305;
    const INVALID_ID: u64 = 400;

    public entry fun sys_user_init(account: &signer, fid: u64, uid: u64, user: address)
    acquires UsersReward
    {
        let _user_address = signer::address_of(account);
        assert!(_user_address == @dat3, error::permission_denied(PERMISSION_DENIED));
        if (!coin::is_account_registered<0x1::aptos_coin::AptosCoin>(user)) {
            create_account(user);
        };
        user_init_fun(user, fid, uid);
    }

    /********************/
    /* FRIEND FUNCTIONS */
    /********************/
    //This method is invoked by the dat3::dat3_core resource account
    public(friend) fun to_reward(admin: &signer) acquires UsersReward
    {
        assert!(signer::address_of(admin) == @dat3_admin, error::permission_denied(PERMISSION_DENIED));
        let usr = borrow_global_mut<UsersReward>(@dat3_reward);
        //index
        let i = 0u64;
        let bucket_keys = smart_tablev1::bucket_keys(&usr.data);
        let leng = vector::length(&bucket_keys);
        let now = timestamp::now_seconds();
        // Get yesterday's key
        let last_key = (((now as u128) - SECONDS_OF_DAY) / SECONDS_OF_DAY as u64);
        let users = vector::empty<address>();
        let today_volume = 0u128;
        while (i < leng) {
            let usr_bucket = smart_tablev1::borrow_bucket<address, Reward>
                (&usr.data, *vector::borrow(&bucket_keys, i));
            let b_len = vector::length(usr_bucket);
            if (b_len > 0) {
                let j = 0u64;
                while (j < b_len) {
                    let en = vector::borrow(usr_bucket, j);
                    let (_address, user) = smart_tablev1::entry(en);
                    if (simple_mapv1::contains_key(&user.taday_earn, &last_key)) {
                        let last_earn = simple_mapv1::borrow(&user.taday_earn, &last_key);
                        if (*last_earn > 0) {
                            today_volume = today_volume + (*last_earn as u128);
                            vector::push_back(&mut users, *_address);
                        }
                    };
                    j = j + 1;
                };
            };
            i = i + 1;
        };
        leng = vector::length(&users);
        i = 0;
        let coins = pool::withdraw_reward_last();
        if (leng > 0) {
            while (i < leng) {
                let user_addr = vector::borrow(&users, i);
                let user_r = smart_tablev1::borrow_mut<address, Reward>(&mut usr.data, *user_addr);
                if (simple_mapv1::contains_key(&user_r.taday_earn, &last_key)) {
                    let last_earn = simple_mapv1::borrow(&user_r.taday_earn, &last_key);
                    if (*last_earn > 0) {
                        let td = (((coins as u128) * (*last_earn as u128) / today_volume) as u64) ;
                        user_r.reward = user_r.reward + td;
                        vector::push_back(&mut user_r.every_dat3_reward, td);
                        vector::push_back(&mut user_r.every_dat3_reward_time, now);
                    }
                };
                i = i + 1;
            };
        };
    }

    // unsafe
    public fun payment_empty_user_init(payment: &signer, user: address, fid: u64, uid: u64) acquires UsersReward
    {
        assert!(signer::address_of(payment) == @dat3_payment, error::invalid_argument(PERMISSION_DENIED));
        empty_user_init(user, fid, uid);
    }

    fun empty_user_init(user: address, fid: u64, uid: u64) acquires UsersReward
    {
        if (!coin::is_account_registered<0x1::aptos_coin::AptosCoin>(user)) {
            create_account(user);
        };
        user_init_fun(user, fid, uid);
    }

    //user init
    fun user_init_fun(
        user_address: address,
        fid: u64,
        uid: u64
    ) acquires UsersReward
    {
        //cheak_fid
        assert!(fid >= 0 && fid <= 5040, error::invalid_argument(INVALID_ID));
        //init UsersReward
        let user_r = borrow_global_mut<UsersReward>(@dat3_reward);

        if (!smart_tablev1::contains(&user_r.data, user_address)) {
            smart_tablev1::add(&mut user_r.data, user_address, Reward {
                uid: 0u64,
                fid: 0u64,
                //call fee
                mFee: 1u64,
                //apt
                reward: 0u64,
                reward_claimed: 0u64,
                //dat3
                reward_dat3: 0u64,
                reward_dat3_claimed: 0u64,
                //talk freeze apt in pool
                taday_spend: 0u64,
                total_spend: 0u64,
                total_earn: 0u64,
                taday_earn: simple_mapv1::create<u64, u64>(),
                every_dat3_reward: vector::empty<u64>(),
                every_dat3_reward_time: vector::empty<u64>()
            });
        }else {
            let user = smart_tablev1::borrow_mut(&mut user_r.data, user_address);
            if (user.fid == 0 && fid > 0 && fid <= 5040) {
                user.fid = fid;
            };
            if (user.uid == 0 && uid > 0) {
                user.uid = uid;
            };
        };
    }

    public entry fun init(owner: &signer)
    {
        let addr = signer::address_of(owner);
        assert!(addr == @dat3, error::already_exists(ALREADY_EXISTS));
        assert!(!exists<SignerCapabilityStore>(@dat3_reward), error::already_exists(ALREADY_EXISTS));

        let (resourceSigner, sinCap) = account::create_resource_account(owner, b"dat3_reward_v1");
        move_to(&resourceSigner, SignerCapabilityStore {
            sinCap
        });
        move_to(&resourceSigner, UsersReward { data: smart_tablev1::new_with_config<address, Reward>(5, 75, 200) });
        let mFee = simple_mapv1::create<u64, u64>();
        simple_mapv1::add(&mut mFee, 1, 10000000);
        simple_mapv1::add(&mut mFee, 2, 50000000);
        simple_mapv1::add(&mut mFee, 3, 100000000);
        simple_mapv1::add(&mut mFee, 4, 300000000);
        simple_mapv1::add(&mut mFee, 5, 1000000000);
        // user: &signer, grade: u64, fee: u64, cfee: u64
        move_to(
            &resourceSigner,
            FeeStore { invite_reward_fee_den: 10000, invite_reward_fee_num: 500, chatFee: 1000000, mFee }
        );
    }

    //claim_reward
    public entry fun claim_dat3_reward(account: &signer) acquires UsersReward
    {
        let user_address = signer::address_of(account);
        assert!(coin::is_account_registered<DAT3>(user_address), error::permission_denied(PERMISSION_DENIED));
        let user_r = borrow_global_mut<UsersReward>(@dat3_reward);
        if (smart_tablev1::contains(&user_r.data, user_address)) {
            let your = smart_tablev1::borrow_mut(&mut user_r.data, user_address);
            if (your.reward_dat3 > 0) {
                pool::withdraw_reward(user_address, your.reward_dat3);
                your.reward_dat3_claimed = your.reward_dat3_claimed + your.reward_dat3;
                your.reward_dat3 = 0;
            };
        };
    }

    //claim_reward
    public entry fun claim_reward(account: &signer) acquires UsersReward
    {
        let user_address = signer::address_of(account);
        let user_r = borrow_global_mut<UsersReward>(@dat3_reward);
        if (smart_tablev1::contains(&user_r.data, user_address)) {
            let your = smart_tablev1::borrow_mut(&mut user_r.data, user_address);
            if (your.reward > 0) {
                pool::withdraw(user_address, your.reward);
                your.reward_claimed = your.reward_claimed + your.reward;
                your.reward = 0;
            };
        };
    }

    //Modify  charging standard
    public entry fun change_sys_fee(user: &signer, grade: u64, fee: u64, cfee: u64) acquires FeeStore
    {
        let user_address = signer::address_of(user);
        assert!(user_address == @dat3, error::permission_denied(PERMISSION_DENIED));
        assert!(grade > 0 && grade <= 5, error::out_of_range(OUT_OF_RANGE));
        assert!(fee > 0, error::out_of_range(OUT_OF_RANGE));
        let fee_s = borrow_global_mut<FeeStore>(@dat3_reward);
        if (cfee > 0) {
            fee_s.chatFee = cfee;
        };
        if (grade > 0) {
            let old_fee = simple_mapv1::borrow_mut(&mut fee_s.mFee, &grade);
            *old_fee = fee;
        };
    }

    public entry fun change_my_fee(user: &signer, grade: u64)
    acquires UsersReward
    {
        let user_address = signer::address_of(user);
        assert!(grade > 0 && grade <= 5, error::out_of_range(OUT_OF_RANGE));
        let member_store = borrow_global_mut<UsersReward>(@dat3_reward);
        if (smart_tablev1::contains(&member_store.data, user_address)) {
            let is_me = smart_tablev1::borrow_mut(&mut member_store.data, user_address);
            is_me.mFee = grade;
        };
    }

    //Modify nft reward data
    public fun distribute_rewards(
        sender: address,
        receiver: address,
        spend: u64,
        coin: Coin<0x1::aptos_coin::AptosCoin>
    )
    acquires SignerCapabilityStore, UsersReward, FeeStore
    {
        let user_r = borrow_global_mut<UsersReward>(@dat3_reward);
        let fees = borrow_global<FeeStore>(@dat3_reward);
        let sig = account::create_signer_with_capability(&borrow_global<SignerCapabilityStore>(@dat3_reward).sinCap);

        //receiver earn
        let rec = smart_tablev1::borrow_mut(&mut user_r.data, receiver);
        let earn = (((spend as u128) * 70 / 100) as u64);
        rec.total_earn = rec.total_earn + earn;
        rec.reward = earn;
        let ea = (((earn as u128) / fees.invite_reward_fee_den * fees.invite_reward_fee_num) as u64);
        //Sent to nft invitation reward
        invitation_reward::invitation_reward(&sig, rec.fid, coin::extract(&mut coin, ea), true) ;
        let now_key = ((timestamp::now_seconds() as u128) / SECONDS_OF_DAY as u64);
        if (simple_mapv1::contains_key(&rec.taday_earn, &now_key)) {
            let t_earn = simple_mapv1::borrow_mut(&mut rec.taday_earn, &now_key);
            *t_earn = *t_earn + earn
        }else {
            let len = simple_mapv1::length(&rec.taday_earn);
            if (len >= 30) {
                let i = 0u64;
                while (i < 10) {
                    let (_, _) = simple_mapv1::remove_index(&mut rec.taday_earn, i);
                    i = i + 1;
                }
            };
            simple_mapv1::add(&mut rec.taday_earn, now_key, earn) ;
        };

        //sender spend
        let req = smart_tablev1::borrow_mut(&mut user_r.data, sender);
        req.total_spend = req.total_spend + spend ;
        req.taday_spend = req.taday_spend + spend ;
        let sp = (((spend as u128) / fees.invite_reward_fee_den * fees.invite_reward_fee_num) as u64);
        //Sent to nft invitation reward
        invitation_reward::invitation_reward(&sig, req.fid, coin::extract(&mut coin, sp), true) ;

        pool::deposit_coin(coin)
    }


    //Modify nft reward data
    fun invitation_reward(fid: u64, den: u128, num: u128, amount: u64, is_spend: bool)
    acquires SignerCapabilityStore {
        let val = (((amount as u128) / den * num) as u64);
        //Get resource account signature
        let sig = account::create_signer_with_capability(&borrow_global<SignerCapabilityStore>(@dat3_reward).sinCap);
        //Withdraw coin  from pool
        let coin = pool::withdraw_coin(val);
        //Sent to nft invitation reward
        invitation_reward::invitation_reward(&sig, fid, coin, is_spend) ;
    }

    public fun add_invitee(owner: &signer, fid: u64, user: address) acquires SignerCapabilityStore {
        assert!(signer::address_of(owner) == @dat3, error::permission_denied(PERMISSION_DENIED));
        let sig = account::create_signer_with_capability(&borrow_global<SignerCapabilityStore>(@dat3_reward).sinCap);
        invitation_reward::add_invitee(&sig, fid, user)
    }

    //get user charging standard ( discard)
    #[view]
    public fun fee_of_mine(user: address): (u64, u64, u64) acquires FeeStore, UsersReward
    {
        let fee_s = borrow_global<FeeStore>(@dat3_reward);
        let user_r = borrow_global<UsersReward>(@dat3_reward);
        if (smart_tablev1::contains(&user_r.data, user)) {
            let is_me = smart_tablev1::borrow(&user_r.data, user);
            return (fee_s.chatFee, is_me.mFee, *simple_mapv1::borrow(&fee_s.mFee, &is_me.mFee))
        };
        return (fee_s.chatFee, 1u64, *simple_mapv1::borrow(&fee_s.mFee, &1u64))
    }
    #[view]
    public fun fee_with(user: address,consumer:address): (u64, u64, u64,u64, u64) acquires FeeStore, UsersReward
    {
        let _apt = 0u64;
        let _dat3 = 0u64;
        if (coin::is_account_registered<0x1::aptos_coin::AptosCoin>(consumer)) {
            _apt = coin::balance<0x1::aptos_coin::AptosCoin>(consumer)
        };
        if (coin::is_account_registered<DAT3>(consumer)) {
            _dat3 = coin::balance<DAT3>(consumer)
        } ;
        let fee_s = borrow_global<FeeStore>(@dat3_reward);
        let user_r = borrow_global<UsersReward>(@dat3_reward);
        if (smart_tablev1::contains(&user_r.data, user)) {
            let is_me = smart_tablev1::borrow(&user_r.data, user);
            return (fee_s.chatFee, is_me.mFee, *simple_mapv1::borrow(&fee_s.mFee, &is_me.mFee),_apt,_dat3)
        };

        return (fee_s.chatFee, 1u64, *simple_mapv1::borrow(&fee_s.mFee, &1u64),_apt,_dat3)
    }
    //get all of charging standard
    #[view]
    public fun fee_of_all(): (u64, vector<u64>) acquires FeeStore
    {
        let fee = borrow_global<FeeStore>(@dat3_reward);
        let vl = vector::empty<u64>();
        vector::push_back(&mut vl, *simple_mapv1::borrow(&fee.mFee, &1));
        vector::push_back(&mut vl, *simple_mapv1::borrow(&fee.mFee, &2));
        vector::push_back(&mut vl, *simple_mapv1::borrow(&fee.mFee, &3));
        vector::push_back(&mut vl, *simple_mapv1::borrow(&fee.mFee, &4));
        vector::push_back(&mut vl, *simple_mapv1::borrow(&fee.mFee, &5));
        (fee.chatFee, vl)
    }


    //get user assets
    #[view]
    public fun assets(addr: address): (u64, u64, u64, u64, u64, u64, u64, u64, u64, u64, u64, u64, u64)
    acquires UsersReward, FeeStore
    {
        let _uid = 0u64;
        let _fid = 0u64;
        let _mFee = 0u64;
        let _reward = 0u64;
        let _reward_claimed = 0u64;
        let _reward_dat3 = 0u64;
        let _reward_dat3_claimed = 0u64;

        let _taday_spend = 0u64;
        let _total_spend = 0u64;
        let _total_earn: u64 = 0;
        let _taday_earn: u64 = 0;
        let user_r = borrow_global<UsersReward>(@dat3_reward);
        let fee_s = borrow_global<FeeStore>(@dat3_reward);

        if (smart_tablev1::contains(&user_r.data, addr)) {
            let r = smart_tablev1::borrow(&user_r.data, addr);
            _uid = r.uid;
            _fid = r.fid;
            _mFee = *simple_mapv1::borrow(&fee_s.mFee, &r.mFee);
            _reward = r.reward;
            _reward_claimed = r.reward_claimed;
            _reward_dat3 = r.reward_dat3;
            _reward_dat3_claimed = r.reward_dat3_claimed;

            _taday_spend = r.total_spend;
            _total_spend = r.total_spend;
            let len = simple_mapv1::length(&r.taday_earn);
            let now_key = ((timestamp::now_seconds() as u128) / SECONDS_OF_DAY as u64);
            let (k, v) = simple_mapv1::find_index(&r.taday_earn, len - 1);
            if (*k == now_key) {
                _taday_earn = *v;
            };
        }  ;
        let _apt = 0u64;
        let _dat3 = 0u64;
        if (coin::is_account_registered<0x1::aptos_coin::AptosCoin>(addr)) {
            _apt = coin::balance<0x1::aptos_coin::AptosCoin>(addr)
        };
        if (coin::is_account_registered<DAT3>(addr)) {
            _dat3 = coin::balance<DAT3>(addr)
        } ;
        (_uid, _fid, _mFee, _apt, _dat3, _reward, _reward_claimed,
            _reward_dat3, _reward_dat3_claimed, _taday_spend, _total_spend, _total_earn, _taday_earn)
    }

    #[view]
    public fun reward_record(addr: address): (u64, u64, u64, u64, vector<u64>, vector<u64>, vector<u64>, vector<u64>, )
    acquires UsersReward
    {
        let _taday_spend = 0u64;
        let _total_spend = 0u64;
        let _total_earn = 0u64;
        let _taday_earn_key = vector::empty<u64>() ;
        let _taday_earn = vector::empty<u64>() ;
        let _dat3 = 0u64;
        let _every_reward_time = vector::empty<u64>();
        let _every_reward = vector::empty<u64>();
        let ueer_r = borrow_global<UsersReward>(@dat3_reward);
        if (smart_tablev1::contains(&ueer_r.data, addr)) {
            let data=&ueer_r.data;
            let r = smart_tablev1::borrow(data, addr);
            _taday_spend = r.taday_spend;
            _total_spend = r.total_spend;
            _total_earn = r.total_earn;
            let len = simple_mapv1::length(&r.taday_earn);
            if (len > 0) {
                let i = 0u64;
                while (i < len) {
                    let (_k, _v) = simple_mapv1::find_index(&r.taday_earn, i);
                    vector::push_back(&mut _taday_earn_key, *_k) ;
                    vector::push_back(&mut _taday_earn, *_v) ;
                };
            };

            _dat3 = r.reward + r.reward_dat3_claimed;
            _every_reward_time = r.every_dat3_reward_time;
            _every_reward = r.every_dat3_reward;
        };
        (_taday_spend, _total_spend, _total_earn, _dat3, _every_reward_time, _every_reward, _taday_earn_key, _taday_earn)
    }

}