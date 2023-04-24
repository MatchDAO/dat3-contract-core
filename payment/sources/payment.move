module dat3::payment {
    use std::error;
    use std::signer;
    use std::string::{Self, String};
    use std::vector;

    use aptos_framework::account::{Self, SignerCapability};
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::coin::{Self, Coin, BurnCapability, FreezeCapability, MintCapability};
    use aptos_framework::timestamp;

    use dat3::dat3_coin::DAT3;
    use dat3::reward;
    use dat3::smart_tablev1::{Self, SmartTablev1};


    #[test_only]
    use dat3::pool;
    #[test_only]
    use aptos_framework::aptos_account::create_account;
    #[test_only]
    use aptos_std::debug;

    friend dat3::interface;

    struct CurrentRoom has key {
        data: SmartTablev1<address, vector<Call>>,
    }

    struct Call has key, drop, copy, store {
        grade: u64,
        time: u64,
    }


    struct DAT3MsgHoder has key, store {
        data: SmartTablev1<address, MsgHoder>
    }


    struct MsgHoder has key, store {
        receive: SmartTablev1<address, vector<u64>>
    }

    struct FreezeStore has key, store {
        freeze: Coin<0x1::aptos_coin::AptosCoin>
    }

    struct SignerCapabilityStore has key, store {
        sinCap: SignerCapability,
    }

    struct HodeCap has key {
        burnCap: BurnCapability<DAT3>,
        freezeCap: FreezeCapability<DAT3>,
        mintCap: MintCapability<DAT3>,
        mintAptCap: MintCapability<AptosCoin>,
        burnAptCap: BurnCapability<AptosCoin>,

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


    //claim_reward
    public entry fun claim_reward(account: &signer)
    {
        reward::claim_reward(account);
    }

    //claim_reward
    public entry fun claim_dat3_reward(account: &signer)
    {
        reward::claim_dat3_reward(account);
    }

    //Modify user charging standard
    public entry fun change_my_fee(account: &signer, grade: u64)
    {
        reward::change_my_fee(account, grade)
    }

    #[view]
    public fun fee_of_mine(account: address): (u64, u64, u64)
    {
        return reward::fee_of_mine(account)
    }

    #[view]
    public fun fee_with(account: address, consumer: address): (u64, u64, u64, u64, u64)
    {
        return reward::fee_with(account, consumer)
    }

    #[view]
    public fun fee_of_all(): (u64, vector<u64>)
    {
        return reward::fee_of_all()
    }

    #[view]
    public fun coin_registered<CoinType>(user: address): bool
    {
        return coin::is_account_registered<CoinType>(user)
    }

    public entry fun coin_register<CoinType>(user: &signer)
    {
        if (!coin::is_account_registered<CoinType>(signer::address_of(user))) {
            coin::register<CoinType>(user)
        }
    }

    #[view]
    public fun assets(account: address): (u64, u64, u64, u64, u64, u64, u64, u64, u64, u64, u64, u64, u64)
    {
        return reward::assets(account)
    }

    #[view]
    public fun reward_record(
        account: address
    ): (u64, u64, u64, u64, vector<u64>, vector<u64>, vector<u64>, vector<u64>, )
    {
        return reward::reward_record(account)
    }

    public entry fun send_msg(account: &signer, to: address)
    acquires DAT3MsgHoder, FreezeStore, SignerCapabilityStore
    {
        let from = signer::address_of(account);
        // check users
        assert!(from != to, error::not_found(NO_TO_USER));
        // is_sender
        let is_sender = add_sender(from, to);

        let dat3_msg = borrow_global_mut<DAT3MsgHoder>(@dat3_payment);
        let now = timestamp::now_seconds();
        if (is_sender == 1) {
            //get fee
            let (chatFee, _, _) = reward::fee_of_mine(to);
            //Verify Balance
            let amount = coin::balance<0x1::aptos_coin::AptosCoin>(from);
            assert!(amount >= chatFee, error::out_of_range(EINSUFFICIENT_BALANCE));
            let to_hoder = smart_tablev1::borrow_mut(&mut dat3_msg.data, to);
            let req_receive = smart_tablev1::borrow_mut(&mut to_hoder.receive, from);
            let unfreeze = 0u64;
            let len = vector::length(req_receive);
            if (len > 0) {
                let i = 0u64;
                while (i < len) {
                    //Message expired, return frozen amount
                    if ((now - *vector::borrow<u64>(req_receive, i)) > SECONDS_OF_12HOUR) {
                        unfreeze = unfreeze + chatFee;
                        vector::swap_remove(req_receive, i);
                        if (len - i >= 1) {
                            len = len - 1;
                        };
                        if (i > 0) {
                            i = i - 1;
                        };
                    };
                    i = i + 1;
                };
            };

            if (!exists<FreezeStore>(from)) {
                move_to(account, FreezeStore { freeze: coin::withdraw<0x1::aptos_coin::AptosCoin>(account, chatFee) });
            }else {
                let fre = borrow_global_mut<FreezeStore>(from);
                if (unfreeze > chatFee && unfreeze <= coin::value(&fre.freeze)) {
                    //The unfrozen amount is greater than the frozen amount
                    coin::deposit<0x1::aptos_coin::AptosCoin>(from, coin::extract(&mut fre.freeze, unfreeze - chatFee))
                }else {
                    coin::merge(&mut fre.freeze, coin::withdraw<0x1::aptos_coin::AptosCoin>(account, chatFee))
                };
            };
            //Record the time of each message
            vector::push_back(req_receive, now)
        };

        //receiver
        if (is_sender == 2) {
            //is receiver
            //get msg_hoder of receiver
            let msg_hoder = smart_tablev1::borrow_mut(&mut dat3_msg.data, from);
            let receive = smart_tablev1::borrow_mut(&mut msg_hoder.receive, to);
            let (chatFee, _, _) = reward::fee_of_mine(to);
            let leng = vector::length(receive);
            if (leng > 0) {
                let i = 0u64;
                // a spend
                let spend = 0u64;
                let now = timestamp::now_seconds();
                while (i < leng) {
                    //Effective time
                    if ((now - *vector::borrow<u64>(receive, i)) < SECONDS_OF_12HOUR) {
                        spend = spend + chatFee;
                    };
                    i = i + 1;
                };
                //reset msg_hoder of sender
                *receive = vector::empty<u64>();
                if (spend > 0) {
                    let fre = borrow_global_mut<FreezeStore>(to);
                    reward::distribute_rewards(to, from, spend, coin::extract(&mut fre.freeze, spend));
                    //receiver   UsersReward earn
                    let back = leng * chatFee - spend;
                    if (back > 0 && coin::value(&fre.freeze) >= back) {
                        coin::deposit(to, coin::extract(&mut fre.freeze, back))
                    };
                };
            };
        }
    }
    public entry fun sys_send_msg(_account: &signer,from:address, to: address)
    acquires DAT3MsgHoder, FreezeStore, SignerCapabilityStore
    {
        // check users
        assert!(from != to, error::not_found(NO_TO_USER));
        // is_sender
        let is_sender = add_sender(from, to);
        let dat3_msg = borrow_global_mut<DAT3MsgHoder>(@dat3_payment);
        if (is_sender == 2) {
            //is receiver
            //get msg_hoder of receiver
            let msg_hoder = smart_tablev1::borrow_mut(&mut dat3_msg.data, from);
            let receive = smart_tablev1::borrow_mut(&mut msg_hoder.receive, to);
            let (chatFee, _, _) = reward::fee_of_mine(to);
            let leng = vector::length(receive);
            if (leng > 0) {
                let i = 0u64;
                // a spend
                let spend = 0u64;
                let now = timestamp::now_seconds();
                while (i < leng) {
                    //Effective time
                    if ((now - *vector::borrow<u64>(receive, i)) < SECONDS_OF_12HOUR) {
                        spend = spend + chatFee;
                    };
                    i = i + 1;
                };
                //reset msg_hoder of sender
                *receive = vector::empty<u64>();
                if (spend > 0) {
                    let fre = borrow_global_mut<FreezeStore>(to);
                    reward::distribute_rewards(to, from, spend, coin::extract(&mut fre.freeze, spend));
                    //receiver   UsersReward earn
                    let back = leng * chatFee - spend;
                    if (back > 0 && coin::value(&fre.freeze) >= back) {
                        coin::deposit(to, coin::extract(&mut fre.freeze, back))
                    };
                };
            };
        }

    }
    //Charge per minute
    public entry fun one_minute(requester: &signer, receiver: address)
    acquires CurrentRoom, SignerCapabilityStore
    {
        let req_addr = signer::address_of(requester);
        // check users
        let sig = account::create_signer_with_capability(&borrow_global<SignerCapabilityStore>(@dat3_payment).sinCap);

        reward::payment_empty_user_init(&sig, receiver, 0u64, 0u64);
        let (_, grade, fee) = reward::fee_of_mine(receiver);
        assert!(fee <= coin::balance<0x1::aptos_coin::AptosCoin>(req_addr), error::aborted(EINSUFFICIENT_BALANCE));

        let current_room = borrow_global_mut<CurrentRoom>(@dat3_payment);
        let now = timestamp::now_seconds();
        if (!smart_tablev1::contains(&current_room.data, req_addr)) {
            smart_tablev1::add(&mut current_room.data, req_addr, vector::singleton(Call { grade, time: now }))
        }else {
            let vec = smart_tablev1::borrow_mut(&mut current_room.data, req_addr);
            let len = vector::length(vec);
            if (len == 0 || (now - vector::borrow(vec, (len - 1)).time) > 90) {
                *vec = vector::singleton(Call { grade, time: now })  ;
            }else {
                vector::push_back(vec, Call { grade, time: now })
            };
        };
        let coin = coin::withdraw<0x1::aptos_coin::AptosCoin>(requester, fee);
        reward::distribute_rewards(req_addr, receiver, fee, coin);
    }

    /********************/
    /* SYS ENTRY FUNCTIONS */
    /********************/

    public entry fun init(owner: &signer)
    {
        let addr = signer::address_of(owner);
        assert!(addr == @dat3, error::permission_denied(PERMISSION_DENIED));
        assert!(!exists<SignerCapabilityStore>(@dat3_payment), error::already_exists(ALREADY_EXISTS));

        let (resourceSigner, sinCap) = account::create_resource_account(owner, b"dat3_payment_v1");
        move_to(&resourceSigner, SignerCapabilityStore {
            sinCap
        });
        //new_with_config<address, Reward>(5, 75, 200)
        move_to(&resourceSigner, DAT3MsgHoder { data: smart_tablev1::new_with_config<address, MsgHoder>(5, 75, 200) });

        move_to(
            &resourceSigner,
            CurrentRoom { data: smart_tablev1::new_with_config<address, vector<Call>>(5, 75, 200) }
        );
    }

    /********************/
    /* FRIEND FUNCTIONS */
    /********************/
    //todo
    // public entry fun unfreeze_talk_reward(_admin: &signer)
    // acquires DAT3MsgHoder, FreezeStore
    // {
    //     let m = borrow_global_mut<DAT3MsgHoder>(@dat3_payment);
    //     let len = smart_tablev1::length(&m.data);
    //     let i = 0u64;
    //     let now = timestamp::now_seconds();
    //     let (chatFee, _) = reward::fee_of_all();
    //     while (i < len) {
    //         let (_address, _msgHoder) = smart_tablev1::bucket_keys(&m.data, i);
    //         let msgHoder = smart_tablev1::borrow_mut(&mut m.data, _address);
    //         let mLen = smart_tablev1::length(&msgHoder.receive);
    //         if (mLen > 0) {
    //             let j = 0u64;
    //             while (j < mLen) {
    //                 let (_sender, msg) = smart_tablev1::find_index(&msgHoder.receive, i);
    //                 let msgLen = vector::length(msg);
    //                 if (msgLen > 0) {
    //                     let unfreeze = 0u64;
    //                     let s = 0u64;
    //                     while (s < msgLen) {
    //                         //Message expired, return frozen amount
    //                         if ((now - *vector::borrow<u64>(msg, i)) > SECONDS_OF_12HOUR) {
    //                             unfreeze = unfreeze + chatFee;
    //                             vector::swap_remove(msg, i);
    //                             if (msgLen - s >= 1) {
    //                                 msgLen = msgLen - 1;
    //                             };
    //                             if (s > 0) {
    //                                 s = s - 1;
    //                             };
    //                         };
    //                         s = s + 1;
    //                     };
    //                     let fs = borrow_global_mut<FreezeStore>(*_sender);
    //                     if (unfreeze > 0 && coin::value(&fs.freeze) >= unfreeze) {
    //                         coin::deposit(*_sender, coin::extract(&mut fs.freeze, unfreeze))
    //                     };
    //                 };
    //                 j = j + 1;
    //             };
    //         };
    //         i = i + 1;
    //     };
    // }

    /*********************/
    /* PRIVATE FUNCTIONS */
    /*********************/


    const NUM_VEC: vector<u8> = b"0123456789";

    fun intToString(_n: u64): String
    {
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

    /*********************/
    /* VIEW FUNCTIONS */
    /*********************/


    public fun add_sender(sender: address, to: address): u64
    acquires DAT3MsgHoder, SignerCapabilityStore {
        let dat3_msg = borrow_global_mut<DAT3MsgHoder>(@dat3_payment);
        let to_init = smart_tablev1::contains(&dat3_msg.data, to) ;
        let sender_init = smart_tablev1::contains(&dat3_msg.data, sender) ;
        //Both are not initialized
        if (!to_init && !sender_init) {
            let sig = account::create_signer_with_capability(
                &borrow_global<SignerCapabilityStore>(@dat3_payment).sinCap
            );
            reward::payment_empty_user_init(&sig, to, 0u64, 0u64);
            reward::payment_empty_user_init(&sig, sender, 0u64, 0u64);
            //
            smart_tablev1::add(&mut dat3_msg.data, sender, MsgHoder {
                receive: smart_tablev1::new_with_config<address, vector<u64>>(5, 75, 200),
            });
            //receive
            let receive = smart_tablev1::new_with_config<address, vector<u64>>(5, 75, 200);
            smart_tablev1::add(&mut receive, sender, vector::empty<u64>());
            smart_tablev1::add(&mut dat3_msg.data, to, MsgHoder {
                receive,
            });
        };
        let sig = account::create_signer_with_capability(&borrow_global<SignerCapabilityStore>(@dat3_payment).sinCap);

        if (to_init && !sender_init) {
            reward::payment_empty_user_init(&sig, sender, 0u64, 0u64);
            smart_tablev1::add(&mut dat3_msg.data, sender, MsgHoder {
                receive: smart_tablev1::new_with_config<address, vector<u64>>(5, 75, 200),
            });
            //receive
            let m1 = smart_tablev1::borrow_mut(&mut dat3_msg.data, to);
            if (!smart_tablev1::contains(&m1.receive, sender)) {
                smart_tablev1::add(&mut m1.receive, sender, vector::empty<u64>()) ;
            };
        };
        if (!to_init && sender_init) {
            reward::payment_empty_user_init(&sig, to, 0u64, 0u64);
            smart_tablev1::add(&mut dat3_msg.data, to, MsgHoder {
                receive: smart_tablev1::new_with_config<address, vector<u64>>(5, 75, 200),
            });
            let m1 = smart_tablev1::borrow(&dat3_msg.data, sender);
            if (smart_tablev1::contains(&m1.receive, to)) {
                return 2u64
            };
        };

        let m1 = smart_tablev1::borrow(&dat3_msg.data, sender);
        //no
        if (smart_tablev1::contains(&m1.receive, to)) {
            return 2u64
        };

        let m2 = smart_tablev1::borrow_mut(&mut dat3_msg.data, to);
        //is
        if (smart_tablev1::contains(&m2.receive, sender)) {
            return 1u64
        };

        if (!smart_tablev1::contains(&m2.receive, sender)) {
            smart_tablev1::add(&mut m2.receive, sender, vector::empty<u64>()) ;
        };
        //is
        return 1u64
    }

    //Determine whether the current user identity is a receiver or a sender
    #[view]
    public fun is_sender(sender: address, to: address): u64
    acquires DAT3MsgHoder {
        let dat3_msg = borrow_global<DAT3MsgHoder>(@dat3_payment);
        let to_init = smart_tablev1::contains(&dat3_msg.data, to) ;
        let sender_init = smart_tablev1::contains(&dat3_msg.data, sender) ;
        //Both are not initialized
        if (!to_init && !sender_init) {
            return 1
        };

        if (to_init && !sender_init) {
            return 1
        };
        if (!to_init && sender_init) {
            let m1 = smart_tablev1::borrow(&dat3_msg.data, sender);
            if (smart_tablev1::contains(&m1.receive, to)) {
                return 2u64
            };
            return 1
        };

        let m1 = smart_tablev1::borrow(&dat3_msg.data, sender);
        let m2 = smart_tablev1::borrow(&dat3_msg.data, to);
        //is
        if (smart_tablev1::contains(&m2.receive, sender)) {
            return 1u64
        };
        //no
        if (smart_tablev1::contains(&m1.receive, to)) {
            return 2u64
        };

        //is
        return 1u64
    }

    #[view]
    public fun view_receive(sender: address, to: address): vector<u64> acquires DAT3MsgHoder {
        let dat3_msg = borrow_global<DAT3MsgHoder>(@dat3_payment);
        if (!smart_tablev1::contains(&dat3_msg.data, sender)) {
            return vector::empty<u64>()
        };
        let to_hode = smart_tablev1::borrow(&dat3_msg.data, sender);
        if (!smart_tablev1::contains(&to_hode.receive, to)) {
            return vector::empty<u64>()
        };
        let receive = smart_tablev1::borrow(&to_hode.receive, to);
        return *receive
    }

    #[view]
    public fun remaining_time(req_addr: address): vector<Call>
    acquires CurrentRoom
    {
        let current_room = borrow_global<CurrentRoom>(@dat3_payment);
        if (smart_tablev1::contains(&current_room.data, req_addr)) {
            return *smart_tablev1::borrow(&current_room.data, req_addr)
        } ;
        return vector::empty<Call>()
    }

    #[test(dat3 = @dat3, _a1 = @dat3_admin, fw = @aptos_framework)]
    fun test(dat3: &signer, _a1: &signer, fw: &signer) acquires DAT3MsgHoder, FreezeStore, SignerCapabilityStore {
        timestamp::set_time_has_started_for_testing(fw);
        timestamp::update_global_time_for_test(100000000000);
        create_account(@dat3);
        create_account(@dat3_admin);
        reward::init(dat3);
        init(dat3);
        let (_burn_cap, _mint_cap) = aptos_framework::aptos_coin::initialize_for_test(fw);
        coin::deposit(signer::address_of(dat3), coin::mint(100111000000, &_mint_cap));
        coin::deposit(signer::address_of(_a1), coin::mint(101110000000, &_mint_cap));
        let (burnCap, freezeCap, mintCap) =
            coin::initialize<DAT3>(dat3,
                string::utf8(b"DAT3_alpha"),
                string::utf8(b"DAT3_alpha"),
                6u8, true);

        pool::init_pool(dat3);
        send_msg(dat3, signer::address_of(_a1));
        let is = is_sender(signer::address_of(dat3), signer::address_of(_a1));
        debug::print(&is);
        let mh = borrow_global_mut<DAT3MsgHoder>(@dat3_payment);
        let s = smart_tablev1::borrow_mut(&mut mh.data, @dat3_admin);
        let f = smart_tablev1::borrow_mut(&mut s.receive, @dat3);
        debug::print(f);
        move_to(dat3, HodeCap { mintCap, freezeCap, burnCap, burnAptCap: _burn_cap, mintAptCap: _mint_cap })
    }
}