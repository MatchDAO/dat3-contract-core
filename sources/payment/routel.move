module dat3::routel {
    use std::error;
    use std::signer;
    use std::string::{Self, String};
    use std::vector;

    use aptos_framework::account::{Self, SignerCapability};
    use aptos_framework::aptos_account::create_account;
    use aptos_framework::coin;
    use aptos_framework::timestamp;

    use aptos_token::token;

    use dat3::dat3_coin::DAT3;
    use dat3::pool;
    use dat3::simple_mapv1::{Self, SimpleMapV1};

    friend dat3::interface;
    struct UsersReward has key, store {
        data: SimpleMapV1<address, Reward>,
    }

    struct FidStore has key, store {
        token: String,
        collection: String,
        data: SimpleMapV1<u64, FidReward>,
    }


    struct FeeStore has key, store {
        invite_reward_fee_den: u128,
        invite_reward_fee_num: u128,
        chatFee: u64,
        mFee: SimpleMapV1<u64, u64>,
    }


    struct CurrentRoom has key, drop, copy {
        data: SimpleMapV1<address, vector<Call>>,
    }

    struct Call has key, drop, copy, store {
        grade: u64,
        time: u64,
    }


    struct MemberStore has key, store {
        member: SimpleMapV1<address, Member>
    }

    struct DAT3MsgHoder has key, store {
        data: SimpleMapV1<address, MsgHoder>
    }

    struct FidReward has key, store, drop {
        fid: u64,
        spend: u64,
        earn: u64,
        users: vector<address>,
        claim: u64,
        amount: u64,
    }

    struct MsgHoder has copy, drop, key, store {
        senders: vector<address>,
        receive: SimpleMapV1<address, vector<u64>>
    }

    struct SignerCapabilityStore has key, store {
        sinCap: SignerCapability,
    }

    struct Reward has drop, key, store {
        taday_spend: u64,
        total_spend: u64,
        earn: u64,
        taday_earn: SimpleMapV1<u64, u64>,
        active: u64,
        active_time: u64,
        //apt
        reward: u64,
        //dat3
        reward_claim: u64,
        every_dat3_reward: vector<u64>,
        every_dat3_reward_time: vector<u64>,
    }

    struct Member has key, store {
        addr: address,
        uid: u64,
        fid: u64,
        amount: u64,
        mFee: u64,

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


    /********************/
    /*   ENTRY FUNCTIONS */
    /********************/

    public entry fun user_init(
        account: &signer,
        fid: u64,
        uid: u64
    ) acquires FidStore, UsersReward, MemberStore, DAT3MsgHoder
    {
        let user_address = signer::address_of(account);
        if (!coin::is_account_registered<DAT3>(user_address)) {
            coin::register<DAT3>(account);
        };
        user_init_fun(user_address, fid, uid);
    }

    // deposit coin to pool
    public entry fun deposit(account: &signer, amount: u64) acquires MemberStore
    {
        let user_address = signer::address_of(account);
        let member_hoder = borrow_global_mut<MemberStore>(@dat3_routel);
        assert!(simple_mapv1::contains_key(&member_hoder.member, &user_address), error::not_found(NO_USER));
        if (!coin::is_account_registered<DAT3>(user_address)) {
            coin::register<DAT3>(account)
        };
        let user = simple_mapv1::borrow_mut(&mut member_hoder.member, &user_address);
        pool::deposit(account, amount);
        user.amount = user.amount + amount;
    }

    //withdraw coin to pool
    public entry fun withdraw(account: &signer, amount: u64) acquires MemberStore
    {
        let user_address = signer::address_of(account);
        let member_hoder = borrow_global_mut<MemberStore>(@dat3_routel);
        if (!coin::is_account_registered<DAT3>(user_address)) {
            coin::register<DAT3>(account)
        };
        assert!(simple_mapv1::contains_key(&member_hoder.member, &user_address), error::not_found(NO_USER));

        let auser = simple_mapv1::borrow_mut(&mut member_hoder.member, &user_address);
        let user_amount = auser.amount;
        assert!(user_amount >= amount, error::out_of_range(EINSUFFICIENT_BALANCE));
        auser.amount = user_amount - amount;
        pool::withdraw(user_address, amount);
    }

    //claim_reward
    public entry fun claim_reward(account: &signer) acquires UsersReward
    {
        let user_address = signer::address_of(account);

        let user_r = borrow_global_mut<UsersReward>(@dat3_routel);
        if (simple_mapv1::contains_key(&user_r.data, &user_address)) {
            let your = simple_mapv1::borrow_mut(&mut user_r.data, &user_address);
            if (!coin::is_account_registered<DAT3>(user_address)) {
                coin::register<DAT3>(account)
            };
            if (your.reward > 0) {
                pool::withdraw_reward(user_address, your.reward);
                your.reward_claim = your.reward_claim + your.reward;
                your.reward = 0;
            };
        };
    }

    //claim_invite_reward ,must have nft
    public entry fun claim_invite_reward(account: &signer, fid: u64) acquires FidStore
    {
        let addr = signer::address_of(account);
        let f_s = borrow_global_mut<FidStore>(@dat3_routel);
        assert!(simple_mapv1::contains_key(&f_s.data, &fid), error::not_found(NOT_FOUND));
        let fid_r = simple_mapv1::borrow_mut(&mut f_s.data, &fid);
        if (!coin::is_account_registered<DAT3>(addr)) {
            coin::register<DAT3>(account);
        };
        let token = f_s.token;
        //prefix supplement
        string::append(&mut token, get_new_token_name(fid));
        let token_id = token::create_token_id_raw(
            @dat3_nft,
            f_s.collection,
            token,
            0
        );
        if (token::balance_of(addr, token_id) > 0 && fid_r.amount > 0) {
            pool::withdraw(addr, fid_r.amount);
            fid_r.claim = fid_r.claim + fid_r.amount;
            fid_r.amount = 0;
        };
    }

    //Modify user charging standard
    public entry fun change_my_fee(user: &signer, grade: u64) acquires MemberStore
    {
        let user_address = signer::address_of(user);
        assert!(grade > 0 && grade <= 5, error::out_of_range(OUT_OF_RANGE));
        let member_store = borrow_global_mut<MemberStore>(@dat3_routel);
        if (simple_mapv1::contains_key(&member_store.member, &user_address)) {
            let is_me = simple_mapv1::borrow_mut(&mut member_store.member, &user_address);
            is_me.mFee = grade;
        };
    }

    public entry fun send_msg(account: &signer, from: address, to: address, count: u64, gas: u64)
    acquires FeeStore, FidStore, UsersReward, DAT3MsgHoder, MemberStore
    {
        assert!(signer::address_of(account) == @dat3, error::permission_denied(PERMISSION_DENIED));
        // check users
        let member_store = borrow_global_mut<MemberStore>(@dat3_routel);
        assert!(simple_mapv1::contains_key(&member_store.member, &from), error::not_found(NO_USER));
        assert!(from != to, error::not_found(NO_TO_USER));
        if (!coin::is_account_registered<DAT3>(from)) {
            coin::register<DAT3>(account);
        };
        //get fee
        let fee_s = borrow_global<FeeStore>(@dat3_routel);
        let is_sender = is_sender(from, to);
        let dat3_msg = borrow_global_mut<DAT3MsgHoder>(@dat3_routel);
        //is_sender Deduction chatFee and add TotalConsumption

        if (is_sender == 4 || is_sender == 5) {
            let user_r = borrow_global_mut<UsersReward>(@dat3_routel);
            if (!simple_mapv1::contains_key(&user_r.data, &from)) {
                simple_mapv1::add(&mut user_r.data, from, Reward {
                    total_spend: 0u64,
                    taday_spend: 0u64, earn: 0, taday_earn: simple_mapv1::create<u64, u64>(
                    ), active: 0, active_time: 0, reward: 0, reward_claim: 0, every_dat3_reward: vector::empty<u64>(
                    ), every_dat3_reward_time: vector::empty<u64>()
                });
            };
            if (!simple_mapv1::contains_key(&user_r.data, &to)) {
                simple_mapv1::add(&mut user_r.data, to, Reward {
                    total_spend: 0u64,
                    taday_spend: 0, earn: 0, taday_earn: simple_mapv1::create<u64, u64>(
                    ), active: 0, active_time: 0, reward: 0, reward_claim: 0, every_dat3_reward: vector::empty<u64>(
                    ), every_dat3_reward_time: vector::empty<u64>()
                });
            };
            if (!simple_mapv1::contains_key(&dat3_msg.data, &from)) {
                simple_mapv1::add(&mut dat3_msg.data, from, MsgHoder {
                    senders: vector::empty<address>(),
                    receive: simple_mapv1::create<address, vector<u64>>(),
                });
            };
            if (!simple_mapv1::contains_key(&dat3_msg.data, &to)) {
                simple_mapv1::add(&mut dat3_msg.data, to, MsgHoder {
                    senders: vector::empty<address>(),
                    receive: simple_mapv1::create<address, vector<u64>>(),
                });
            };
            //add member
            if (!simple_mapv1::contains_key(&mut member_store.member, &to)) {
                simple_mapv1::add(&mut member_store.member, to, Member {
                    addr: to,
                    uid: 0u64,
                    fid: 0u64,
                    amount: 0,
                    mFee: 1,
                })
            };
            if (!simple_mapv1::contains_key(&mut member_store.member, &from)) {
                simple_mapv1::add(&mut member_store.member, from, Member {
                    addr: from,
                    uid: 0u64,
                    fid: 0u64,
                    amount: 0,
                    mFee: 1,
                })
            };
        };
        if (is_sender == 1 || is_sender == 3 || is_sender == 5) {
            //init hoder
            if (is_sender == 5) {
                //init to MsgHoder
                if (!simple_mapv1::contains_key(&dat3_msg.data, &to)) {
                    let receive = simple_mapv1::create<address, vector<u64>>();
                    simple_mapv1::add(&mut receive, from, vector::empty<u64>());

                    simple_mapv1::add(&mut dat3_msg.data, to, MsgHoder {
                        senders: vector::singleton<address>(from),
                        receive,
                    });
                }else {
                    let to = simple_mapv1::borrow_mut(&mut dat3_msg.data, &to);
                    if (!vector::contains(&mut to.senders, &from)) {
                        vector::push_back(&mut to.senders, from);
                    };
                    if (!simple_mapv1::contains_key(&to.receive, &from)) {
                        simple_mapv1::add(&mut to.receive, from, vector::empty<u64>())
                    };
                };
            };
            let req_member = simple_mapv1::borrow_mut(&mut member_store.member, &from);
            //check balance
            assert!(req_member.amount >= (fee_s.chatFee * count + gas), error::out_of_range(EINSUFFICIENT_BALANCE));
            //borrow_mut to_msg_hoder
            //add sender init receiver
            if (is_sender == 3) {
                //add sender
                let to_hoder = simple_mapv1::borrow_mut(&mut dat3_msg.data, &to);
                vector::push_back(&mut to_hoder.senders, from);
                if (!simple_mapv1::contains_key(&to_hoder.receive, &from)) {
                    simple_mapv1::add(&mut to_hoder.receive, from, vector::empty<u64>());
                };
            };
            //Record the time of each message
            let to_hoder = simple_mapv1::borrow_mut(&mut dat3_msg.data, &to);
            let req_receive = simple_mapv1::borrow_mut(&mut to_hoder.receive, &from);
            let i = 0u64;
            req_member.amount = req_member.amount - gas;
            while (i < count) {
                vector::push_back(req_receive, timestamp::now_seconds());
                req_member.amount = req_member.amount - fee_s.chatFee;
                i = i + 1;
            };
        };
        //receiver
        if (is_sender == 2) {
            //is receiver
            //get msg_hoder of receiver
            let msg_hoder = simple_mapv1::borrow_mut(&mut dat3_msg.data, &from);
            let receive = simple_mapv1::borrow_mut(&mut msg_hoder.receive, &to);
            let leng = vector::length(receive);
            if (leng > 0) {
                let i = 0u64;
                let spend = 0u64;
                let now = timestamp::now_seconds();
                while (i < leng) {
                    //Effective time
                    if ((now - *vector::borrow<u64>(receive, i)) < SECONDS_OF_12HOUR) {
                        spend = spend + fee_s.chatFee;
                    };
                    i = i + 1;
                };
                //reset msg_hoder of sender
                *receive = vector::empty<u64>();
                if (spend > 0) {
                    let rec_member = simple_mapv1::borrow_mut(&mut member_store.member, &from);
                    let earn = (((spend as u128) * 70 / 100) as u64);
                    rec_member.amount = rec_member.amount + earn - gas;
                    //receiver   UsersReward earn
                    let ur = borrow_global_mut<UsersReward>(@dat3_routel);
                    let rec = simple_mapv1::borrow_mut(&mut ur.data, &from);
                    rec.earn = rec.earn + earn ;
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

                    let req = simple_mapv1::borrow_mut(&mut ur.data, &to);
                    req.total_spend = req.total_spend + spend ;

                    req.taday_spend = req.taday_spend + spend ;
                    fid_re(rec_member.fid, fee_s.invite_reward_fee_den, fee_s.invite_reward_fee_num, earn, false);
                };
                let back = leng * fee_s.chatFee - spend;
                let req_member = simple_mapv1::borrow_mut(&mut member_store.member, &to);
                fid_re(req_member.fid, fee_s.invite_reward_fee_den, fee_s.invite_reward_fee_num, spend, true);
                if (back > 0) {
                    req_member.amount = req_member.amount + back;
                };
            };
        };
    }

    public entry fun call_1(account: &signer, to: address)
    acquires FeeStore, FidStore, UsersReward, DAT3MsgHoder, MemberStore
    {
        let user_address = signer::address_of(account);
        // check users
        let member_store = borrow_global_mut<MemberStore>(@dat3_routel);
        assert!(simple_mapv1::contains_key(&member_store.member, &user_address), error::not_found(NO_USER));
        assert!(user_address != to, error::not_found(NO_TO_USER));
        if (!coin::is_account_registered<DAT3>(user_address)) {
            coin::register<DAT3>(account);
        };
        //get fee
        let fee_s = borrow_global<FeeStore>(@dat3_routel);
        let is_sender = is_sender(user_address, to);
        let dat3_msg = borrow_global_mut<DAT3MsgHoder>(@dat3_routel);
        //is_sender Deduction chatFee and add TotalConsumption

        if (is_sender == 4 || is_sender == 5) {
            let user_r = borrow_global_mut<UsersReward>(@dat3_routel);
            if (!simple_mapv1::contains_key(&user_r.data, &user_address)) {
                simple_mapv1::add(&mut user_r.data, user_address, Reward {
                    total_spend: 0u64,
                    taday_spend: 0, earn: 0, taday_earn: simple_mapv1::create<u64, u64>(
                    ), active: 0, active_time: 0, reward: 0, reward_claim: 0, every_dat3_reward: vector::empty<u64>(
                    ), every_dat3_reward_time: vector::empty<u64>()
                });
            };
            if (!simple_mapv1::contains_key(&user_r.data, &to)) {
                simple_mapv1::add(&mut user_r.data, to, Reward {
                    total_spend: 0u64,
                    taday_spend: 0, earn: 0, taday_earn: simple_mapv1::create<u64, u64>(
                    ), active: 0, active_time: 0, reward: 0, reward_claim: 0, every_dat3_reward: vector::empty<u64>(
                    ), every_dat3_reward_time: vector::empty<u64>()
                });
            };
            if (!simple_mapv1::contains_key(&dat3_msg.data, &user_address)) {
                simple_mapv1::add(&mut dat3_msg.data, user_address, MsgHoder {
                    senders: vector::empty<address>(),
                    receive: simple_mapv1::create<address, vector<u64>>(),
                });
            };
            if (!simple_mapv1::contains_key(&dat3_msg.data, &to)) {
                simple_mapv1::add(&mut dat3_msg.data, to, MsgHoder {
                    senders: vector::empty<address>(),
                    receive: simple_mapv1::create<address, vector<u64>>(),
                });
            };
            //add member
            if (!simple_mapv1::contains_key(&mut member_store.member, &to)) {
                simple_mapv1::add(&mut member_store.member, to, Member {
                    addr: to,
                    uid: 0u64,
                    fid: 0u64,
                    amount: 0,
                    mFee: 1,
                })
            };
        };
        if (is_sender == 1 || is_sender == 3 || is_sender == 5) {
            //init hoder
            if (is_sender == 5) {
                //init UsersReward
                let user_r = borrow_global_mut<UsersReward>(@dat3_routel);
                if (!simple_mapv1::contains_key(&user_r.data, &to)) {
                    simple_mapv1::add(&mut user_r.data, to, Reward {
                        total_spend: 0u64,
                        taday_spend: 0, earn: 0, taday_earn: simple_mapv1::create<u64, u64>(
                        ), active: 0, active_time: 0, reward: 0, reward_claim: 0, every_dat3_reward: vector::empty<u64>(
                        ), every_dat3_reward_time: vector::empty<u64>()
                    });
                };
                //add member

                if (!simple_mapv1::contains_key(&mut member_store.member, &to)) {
                    simple_mapv1::add(&mut member_store.member, to, Member {
                        addr: to,
                        uid: 0u64,
                        fid: 0u64,
                        amount: 0,
                        mFee: 1,
                    })
                };
                //init to MsgHoder
                if (!simple_mapv1::contains_key(&dat3_msg.data, &to)) {
                    let senders = vector::empty<address>();
                    vector::push_back(&mut senders, user_address);
                    let receive = simple_mapv1::create<address, vector<u64>>();
                    simple_mapv1::add(&mut receive, user_address, vector::empty<u64>());
                    simple_mapv1::add(&mut dat3_msg.data, to, MsgHoder {
                        senders,
                        receive,
                    });
                }else {
                    let to = simple_mapv1::borrow_mut(&mut dat3_msg.data, &to);
                    if (!vector::contains(&mut to.senders, &user_address)) {
                        vector::push_back(&mut to.senders, user_address);
                    };
                    if (!simple_mapv1::contains_key(&to.receive, &user_address)) {
                        simple_mapv1::add(&mut to.receive, user_address, vector::empty<u64>())
                    };
                };
            };
            let req_member = simple_mapv1::borrow_mut(&mut member_store.member, &user_address);
            //check balance
            assert!(req_member.amount >= fee_s.chatFee, error::out_of_range(EINSUFFICIENT_BALANCE));
            //borrow_mut to_msg_hoder
            //add sender init receiver
            if (is_sender == 3) {
                //add sender
                let to_hoder = simple_mapv1::borrow_mut(&mut dat3_msg.data, &to);
                vector::push_back(&mut to_hoder.senders, user_address);
                if (!simple_mapv1::contains_key(&to_hoder.receive, &user_address)) {
                    simple_mapv1::add(&mut to_hoder.receive, user_address, vector::empty<u64>());
                };
            };
            //Record the time of each message
            let to_hoder = simple_mapv1::borrow_mut(&mut dat3_msg.data, &to);
            let req_receive = simple_mapv1::borrow_mut(&mut to_hoder.receive, &user_address);
            vector::push_back(req_receive, timestamp::now_seconds());
            req_member.amount = req_member.amount - fee_s.chatFee;
        };
        //receiver
        if (is_sender == 2) {
            if (!coin::is_account_registered<DAT3>(user_address)) {
                coin::register<DAT3>(account);
            };
            //is receiver
            //get msg_hoder of receiver
            let msg_hoder = simple_mapv1::borrow_mut(&mut dat3_msg.data, &user_address);
            let receive = simple_mapv1::borrow_mut(&mut msg_hoder.receive, &to);
            let leng = vector::length(receive);
            if (leng > 0) {
                let i = 0u64;
                let spend = 0u64;
                let now = timestamp::now_seconds();
                while (i < leng) {
                    //Effective time
                    if ((now - *vector::borrow<u64>(receive, i)) < SECONDS_OF_12HOUR) {
                        spend = spend + fee_s.chatFee;
                    };
                    i = i + 1;
                };
                //reset msg_hoder of sender
                *receive = vector::empty<u64>();
                if (spend > 0) {
                    let rec_member = simple_mapv1::borrow_mut(&mut member_store.member, &user_address);
                    let earn = (((spend as u128) * 70 / 100) as u64);
                    rec_member.amount = rec_member.amount + earn;
                    //receiver   UsersReward earn
                    let ur = borrow_global_mut<UsersReward>(@dat3_routel);
                    let rec = simple_mapv1::borrow_mut(&mut ur.data, &user_address);
                    rec.earn = rec.earn + earn ;

                    let req = simple_mapv1::borrow_mut(&mut ur.data, &to);
                    req.total_spend = req.total_spend + spend ;
                    req.taday_spend = req.taday_spend + spend ;
                    fid_re(rec_member.fid, fee_s.invite_reward_fee_den, fee_s.invite_reward_fee_num, earn, false);
                };
                let back = leng * fee_s.chatFee - spend;
                let req_member = simple_mapv1::borrow_mut(&mut member_store.member, &to);
                fid_re(req_member.fid, fee_s.invite_reward_fee_den, fee_s.invite_reward_fee_num, spend, true);
                if (back > 0) {
                    req_member.amount = req_member.amount + back;
                };
            };
        };
    }

    //Charge per minute
    public entry fun one_minute(requester: &signer, receiver: address, grade: u64, )
    acquires MemberStore, FidStore, UsersReward, CurrentRoom, FeeStore
    {
        let req_addr = signer::address_of(requester);
        // check users
        let member_store = borrow_global_mut<MemberStore>(@dat3_routel);
        assert!(simple_mapv1::contains_key(&member_store.member, &req_addr), error::not_found(NO_USER));
        if (!coin::is_account_registered<DAT3>(req_addr)) {
            coin::register<DAT3>(requester);
        };
        //init receiver
        if (!simple_mapv1::contains_key(&member_store.member, &receiver)) {
            //init UsersReward
            let user_r = borrow_global_mut<UsersReward>(@dat3_routel);
            if (!simple_mapv1::contains_key(&user_r.data, &receiver)) {
                simple_mapv1::add(&mut user_r.data, receiver, Reward {
                    total_spend: 0u64,
                    taday_spend: 0, earn: 0, taday_earn: simple_mapv1::create<u64, u64>(
                    ), active: 0, active_time: 0, reward: 0, reward_claim: 0, every_dat3_reward: vector::empty<u64>(
                    ), every_dat3_reward_time: vector::empty<u64>()
                });
            };
            //add member
            simple_mapv1::add(&mut member_store.member, receiver, Member {
                addr: receiver,
                uid: 0u64,
                fid: 0u64,
                amount: 0,
                mFee: 1,
            })
        };


        let req_user = simple_mapv1::borrow_mut(&mut member_store.member, &req_addr);

        let fee_store = borrow_global_mut<FeeStore>(@dat3_routel);
        let gr = grade;
        //get fee
        let fee = simple_mapv1::borrow(&fee_store.mFee, &gr);
        assert!(*fee <= req_user.amount, error::aborted(EINSUFFICIENT_BALANCE));

        let current_room = borrow_global_mut<CurrentRoom>(@dat3_routel);
        let now = timestamp::now_seconds();
        if (!simple_mapv1::contains_key(&current_room.data, &req_addr)) {
            simple_mapv1::add(&mut current_room.data, req_addr, vector::singleton(Call { grade, time: now }))
        }else {
            let vec = simple_mapv1::borrow_mut(&mut current_room.data, &req_addr);
            let len = vector::length(vec);
            if (len == 0 || (now - vector::borrow(vec, (len - 1)).time) > 90) {
                *vec = vector::singleton(Call { grade, time: now })  ;
            }else {
                vector::push_back(vec, Call { grade, time: now })
            };
        };

        req_user.amount = req_user.amount - *fee;
        let ur = borrow_global_mut<UsersReward>(@dat3_routel);
        let req_reward = simple_mapv1::borrow_mut(&mut ur.data, &req_addr);
        req_reward.taday_spend = req_reward.taday_spend + *fee ;
        req_reward.total_spend = req_reward.total_spend + *fee ;

        if (req_user.fid != 0) {
            fid_re(req_user.fid, fee_store.invite_reward_fee_den, fee_store.invite_reward_fee_num, *fee, true);
        };
        let earn = (((*fee * 70 as u128) / (100u128)) as u64);
        let rec_user = simple_mapv1::borrow_mut(&mut member_store.member, &receiver);
        rec_user.amount = rec_user.amount + earn;
        let rec_reward = simple_mapv1::borrow_mut(&mut ur.data, &receiver);
        rec_reward.earn = rec_reward.earn + earn ;
        let now_key = ((timestamp::now_seconds() as u128) / SECONDS_OF_DAY as u64);
        if (simple_mapv1::contains_key(&rec_reward.taday_earn, &now_key)) {
            let t_earn = simple_mapv1::borrow_mut(&mut rec_reward.taday_earn, &now_key);
            *t_earn = *t_earn + earn
        }else {
            let len = simple_mapv1::length(&rec_reward.taday_earn);
            if (len >= 30) {
                let i = 0u64;
                while (i < 10) {
                    let (_, _) = simple_mapv1::remove_index(&mut rec_reward.taday_earn, i);
                    i = i + 1;
                }
            };
            simple_mapv1::add(&mut rec_reward.taday_earn, now_key, earn) ;
        };
        //earn
        if (rec_user.fid != 0) {
            fid_re(rec_user.fid, fee_store.invite_reward_fee_den, fee_store.invite_reward_fee_num, earn, false);
        };
    }

    /********************/
    /* SYS ENTRY FUNCTIONS */
    /********************/

    public entry fun init(owner: &signer)
    {
        let addr = signer::address_of(owner);
        assert!(addr == @dat3, error::permission_denied(PERMISSION_DENIED));
        assert!(!exists<SignerCapabilityStore>(@dat3_routel), error::already_exists(ALREADY_EXISTS));

        let (resourceSigner, sinCap) = account::create_resource_account(owner, b"dat3_routel");
        move_to(&resourceSigner, SignerCapabilityStore {
            sinCap
        });
        move_to(&resourceSigner, UsersReward { data: simple_mapv1::create<address, Reward>() });

        move_to(&resourceSigner, FidStore {
            collection: string::utf8(b"DAT3 invitation NFT"),
            token: string::utf8(b"DAT3 invitation NFT#"),
            data: simple_mapv1::create<u64, FidReward>()
        });

        let mFee = simple_mapv1::create<u64, u64>();
        simple_mapv1::add(&mut mFee, 1, 20000000);
        simple_mapv1::add(&mut mFee, 2, 70000000);
        simple_mapv1::add(&mut mFee, 3, 350000000);
        simple_mapv1::add(&mut mFee, 4, 700000000);
        simple_mapv1::add(&mut mFee, 5, 2100000000);
        move_to(
            &resourceSigner,
            FeeStore { invite_reward_fee_den: 10000, invite_reward_fee_num: 500, chatFee: 1000000, mFee }
        );
        move_to(&resourceSigner, MemberStore { member: simple_mapv1::create<address, Member>() });
        move_to(&resourceSigner, DAT3MsgHoder { data: simple_mapv1::create<address, MsgHoder>() });
        move_to(&resourceSigner, CurrentRoom { data: simple_mapv1::create<address, vector<Call>>() });
    }

    public entry fun sys_user_init(account: &signer, fid: u64, uid: u64, user: address
    ) acquires FidStore, UsersReward, MemberStore, DAT3MsgHoder
    {
        let _user_address = signer::address_of(account);
        assert!(_user_address == @dat3, error::permission_denied(PERMISSION_DENIED));
        if (!coin::is_account_registered<0x1::aptos_coin::AptosCoin>(user)) {
            create_account(user);
        };
        user_init_fun(user, fid, uid);
    }


    //Modify  charging standard
    public entry fun change_sys_fee(user: &signer, grade: u64, fee: u64, cfee: u64) acquires FeeStore
    {
        let user_address = signer::address_of(user);
        assert!(user_address == @dat3, error::permission_denied(PERMISSION_DENIED));
        assert!(grade > 0 && grade <= 5, error::out_of_range(OUT_OF_RANGE));
        assert!(fee > 0, error::out_of_range(OUT_OF_RANGE));
        let fee_s = borrow_global_mut<FeeStore>(@dat3_routel);
        if (cfee > 0) {
            fee_s.chatFee = cfee;
        };
        if (grade > 0) {
            let old_fee = simple_mapv1::borrow_mut(&mut fee_s.mFee, &grade);
            *old_fee = fee;
        };
    }

    //Add or delete nftid
    public entry fun change_sys_fid(user: &signer, fid: u64, del: bool, token: String, collection: String)
    acquires FidStore
    {
        let user_address = signer::address_of(user);
        assert!(user_address == @dat3, error::permission_denied(PERMISSION_DENIED));
        assert!(exists<FidStore>(@dat3_routel), error::permission_denied(PERMISSION_DENIED));
        let f = borrow_global_mut<FidStore>(@dat3_routel);

        let contains = simple_mapv1::contains_key(&f.data, &fid);
        if (contains) {
            let fr = simple_mapv1::borrow_mut(&mut f.data, &fid);
            if (del) {
                assert!(fr.amount == 0
                    && vector::length(&fr.users) == 0
                    && fr.earn == 0
                    && fr.spend == 0
                    && fr.amount == 0, error::permission_denied(ALREADY_EXISTS));
                simple_mapv1::remove(&mut f.data, &fid);
            }else {
                if (collection != f.collection) {
                    f.collection = collection;
                    f.token = token;
                };
            };
        }
    }

    public entry fun sys_call_1(
        _account: &signer,
        sender: address,
        to: address,
        gas: u64
    ) acquires DAT3MsgHoder, FeeStore, MemberStore, UsersReward, FidStore
    {
        let user_address = signer::address_of(_account);
        assert!(user_address == @dat3, error::permission_denied(PERMISSION_DENIED));
        //is receiver
        //get msg_hoder of receiver
        let dat3_msg = borrow_global_mut<DAT3MsgHoder>(@dat3_routel);
        //get fee
        let fee_s = borrow_global<FeeStore>(@dat3_routel);
        let member_store = borrow_global_mut<MemberStore>(@dat3_routel);

        let msg_hoder = simple_mapv1::borrow_mut(&mut dat3_msg.data, &to);
        if (simple_mapv1::contains_key(&msg_hoder.receive, &sender)) {
            let receive = simple_mapv1::borrow_mut(&mut msg_hoder.receive, &sender);
            let leng = vector::length(receive);
            if (leng > 0) {
                let i = 0u64;
                let spend = 0u64;
                let now = timestamp::now_seconds();
                while (i < leng) {
                    //Effective time
                    if ((now - *vector::borrow<u64>(receive, i)) < SECONDS_OF_12HOUR) {
                        spend = spend + fee_s.chatFee;
                    };
                    i = i + 1;
                };
                //reset msg_hoder of sender
                *receive = vector::empty<u64>();
                if (spend > 0) {
                    let rec_member = simple_mapv1::borrow_mut(&mut member_store.member, &to);
                    let earn = (((spend as u128) * 70 / 100) as u64);
                    let rounding = earn - gas;
                    rec_member.amount = rec_member.amount + rounding;

                    //receiver   UsersReward earn
                    let ur = borrow_global_mut<UsersReward>(@dat3_routel);
                    let rec = simple_mapv1::borrow_mut(&mut ur.data, &to);
                    rec.earn = rec.earn + earn ;

                    let req = simple_mapv1::borrow_mut(&mut ur.data, &sender);
                    req.total_spend = req.total_spend + spend ;
                    req.taday_spend = req.taday_spend + spend ;
                    fid_re(rec_member.fid, fee_s.invite_reward_fee_den, fee_s.invite_reward_fee_num, earn, false);
                };
                let back = leng * fee_s.chatFee - spend;
                let req_member = simple_mapv1::borrow_mut(&mut member_store.member, &sender);
                fid_re(req_member.fid, fee_s.invite_reward_fee_den, fee_s.invite_reward_fee_num, spend, true);
                if (back > 0) {
                    req_member.amount = req_member.amount + back;
                };
            };
        };
    }

    /********************/
    /* FRIEND FUNCTIONS */
    /********************/
    //This method is invoked by the dat3::dat3_core resource account
    public(friend) fun to_reward(admin: &signer) acquires UsersReward, DAT3MsgHoder, MemberStore, FeeStore
    {
        assert!(signer::address_of(admin) == @dat3_admin, error::permission_denied(PERMISSION_DENIED));
        let usr = borrow_global_mut<UsersReward>(@dat3_routel);
        //index
        let i = 0u64;
        let leng = simple_mapv1::length(&usr.data);
        let now = timestamp::now_seconds();
        // Get yesterday's key
        let last_key = (((now as u128) - SECONDS_OF_DAY) / SECONDS_OF_DAY as u64);
        let users = vector::empty<address>();
        let today_volume = 0u128;
        while (i < leng) {
            let (address, user) = simple_mapv1::find_index(&usr.data, i);
            if (simple_mapv1::contains_key(&user.taday_earn, &last_key)) {
                let last_earn = simple_mapv1::borrow(&user.taday_earn, &last_key);
                if (*last_earn > 0) {
                    today_volume = today_volume + (*last_earn as u128);
                    vector::push_back(&mut users, *address);
                }
            };
            i = i + 1;
        };
        leng = vector::length(&users);
        i = 0;
        let coins = pool::withdraw_reward_last();
        if (leng > 0) {
            while (i < leng) {
                let user_addr = vector::borrow(&users, i);
                let user_r = simple_mapv1::borrow_mut(&mut usr.data, user_addr);
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

        let dat3_msg = borrow_global_mut<DAT3MsgHoder>(@dat3_routel);
        let len = simple_mapv1::length(&dat3_msg.data);
        let user_s = borrow_global_mut<MemberStore>(@dat3_routel);
        let fee = borrow_global<FeeStore>(@dat3_routel);
        i = 0;
        while (i < len) {
            let (_address, msgs) = simple_mapv1::find_index_mut(&mut dat3_msg.data, i);
            let r_len = simple_mapv1::length(&msgs.receive);
            if (r_len > 0) {
                let (_address, all) = simple_mapv1::find_index_mut(&mut msgs.receive, i);
                let a_len = vector::length(all);
                if (a_len > 0) {
                    let s = 0u64;
                    let count = 0u64;
                    while (s > a_len) {
                        if (now - *vector::borrow(all, s) > SECONDS_OF_12HOUR) {
                            count = count + 1;
                            vector::swap_remove(all,s);
                            if (s > 1) {
                                s = s - 1;
                            };
                            if ((a_len - s) > 1) {
                                a_len = a_len - 1;
                            };
                        };
                        s = s + 1;
                    };
                    if (count > 0) {
                        if(simple_mapv1::contains_key(&user_s.member,_address)){
                          let you=  simple_mapv1::borrow_mut(&mut user_s.member,_address);
                            you.amount=you.amount + count * fee.chatFee
                        };
                    };
                };
            };
            i = i + 1;
        };
    }

    /*********************/
    /* PRIVATE FUNCTIONS */
    /*********************/

    //user init
    fun user_init_fun(
        user_address: address,
        fid: u64,
        uid: u64
    ) acquires FidStore, UsersReward, MemberStore, DAT3MsgHoder
    {
        //cheak_fid
        assert!(fid > 0 && fid <= 5040, error::invalid_argument(INVALID_ID));
        let fids_tore = borrow_global_mut<FidStore>(@dat3_routel);

        //init UsersReward
        let user_r = borrow_global_mut<UsersReward>(@dat3_routel);
        if (!simple_mapv1::contains_key(&user_r.data, &user_address)) {
            simple_mapv1::add(&mut user_r.data, user_address, Reward {
                total_spend: 0u64,
                taday_spend: 0u64,
                earn: 0u64,
                active: 0u64,
                active_time: 0u64,
                taday_earn: simple_mapv1::create<u64, u64>(),
                reward: 0u64, reward_claim: 0u64, every_dat3_reward: vector::empty<u64>(
                ), every_dat3_reward_time: vector::empty<u64>()
            });
        };
        if (fid > 0) {
            if (!simple_mapv1::contains_key(&mut fids_tore.data, &fid)) {
                simple_mapv1::add(&mut fids_tore.data, fid, FidReward {
                    fid,
                    spend: 0,
                    earn: 0,
                    users: vector::empty<address>(),
                    claim: 0,
                    amount: 0,
                })
            };
            //add to FidStore.users
            let fidr = simple_mapv1::borrow_mut(&mut fids_tore.data, &fid);
            if (!vector::contains(&mut fidr.users, &user_address)) {
                vector::push_back(&mut fidr.users, user_address);
            };
        };
        //add member
        let member_hoder = borrow_global_mut<MemberStore>(@dat3_routel);
        if (!simple_mapv1::contains_key(&mut member_hoder.member, &user_address)) {
            simple_mapv1::add(&mut member_hoder.member, user_address, Member {
                addr: user_address,
                uid,
                fid,
                amount: 0,
                mFee: 1,
            })
        }else {
            let user = simple_mapv1::borrow_mut(&mut member_hoder.member, &user_address);
            if (user.fid == 0 && fid > 0 && fid <= 5040) {
                user.fid = fid;
            };
            if (user.uid == 0 && uid > 0) {
                user.uid = uid;
            };
        };
        let dat3_msg = borrow_global_mut<DAT3MsgHoder>(@dat3_routel);
        if (!simple_mapv1::contains_key(&dat3_msg.data, &user_address)) {
            simple_mapv1::add(&mut dat3_msg.data, user_address, MsgHoder {
                senders: vector::empty<address>(),
                receive: simple_mapv1::create<address, vector<u64>>(),
            });
        };
    }
    fun get_new_token_name(i: u64): String
    {
        let name = string::utf8(b"");
        if (i >= 1000) {
            name = string::utf8(b"");
        }else if (100 <= i && i < 1000) {
            name = string::utf8(b"0");
        } else if (10 <= i && i < 100) {
            name = string::utf8(b"00");
        }else if (i < 10) {
            name = string::utf8(b"000");
        };
        string::append(&mut name, intToString(i));
        name
    }
    //Modify nft reward data
    fun fid_re(fid: u64, den: u128, num: u128, amount: u64, is_spend: bool) acquires FidStore
    {
        let f = borrow_global_mut<FidStore>(@dat3_routel);
        if (simple_mapv1::contains_key(&f.data, &fid)) {
            let fr = simple_mapv1::borrow_mut(&mut f.data, &fid);
            let val = (((amount as u128) / den * num) as u64);
            if (is_spend) {
                fr.spend = fr.spend + val;
            }else {
                fr.earn = fr.earn + val;
            };
            fr.amount = fr.amount + val;
        };
    }

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

    //get user assets
    #[view]
    public fun assets(addr: address): (u64, u64, u64, u64, u64, u64, u64, u64, u64, u64)
    acquires UsersReward, MemberStore
    {
        let _uid = 0u64;
        let _fid = 0u64;
        let _mFee = 0u64;
        let _amount = 0u64;
        let member_store = borrow_global<MemberStore>(@dat3_routel);
        if (simple_mapv1::contains_key(&member_store.member, &addr)) {
            let user = simple_mapv1::borrow(&member_store.member, &addr);
            _uid = user.uid;
            _fid = user.fid;
            _mFee = user.mFee;
            _amount = user.amount;
        };
        let user_r = borrow_global<UsersReward>(@dat3_routel);
        let _taday_spend = 0u64;
        let _total_spend = 0u64;
        let _earn: u64 = 0;
        let _active: u64 = 0;
        let _reward: u64 = 0;
        let _claim: u64 = 0;
        if (simple_mapv1::contains_key(&user_r.data, &addr)) {
            let your_reward = simple_mapv1::borrow(&user_r.data, &addr);
            _taday_spend = your_reward.taday_spend;
            _total_spend = your_reward.total_spend;
            _earn = your_reward.earn;

            _active = your_reward.active;
            _reward = your_reward.reward;
            _claim = your_reward.reward_claim;
            _taday_spend = your_reward.taday_spend;
        };
        let _apt = 0u64;
        let _dat3 = 0u64;
        if (coin::is_account_registered<0x1::aptos_coin::AptosCoin>(addr)) {
            _apt = coin::balance<0x1::aptos_coin::AptosCoin>(addr)
        };
        if (coin::is_account_registered<DAT3>(addr)) {
            _dat3 = coin::balance<DAT3>(addr)
        } ;
        (_uid, _fid, _mFee, _apt, _dat3, _amount, _reward, _claim, _taday_spend, _total_spend)
    }

    #[view]
    public fun reward_record(addr: address): (u64, u64, u64, u64, vector<u64>, vector<u64>, vector<u64>, vector<u64>, )
    acquires UsersReward
    {
        let _taday_spend = 0u64;
        let _total_spend = 0u64;
        let _earn = 0u64;
        let _taday_earn_key = vector::empty<u64>() ;
        let _taday_earn = vector::empty<u64>() ;
        let _dat3 = 0u64;
        let _every_reward_time = vector::empty<u64>();
        let _every_reward = vector::empty<u64>();
        let ueer_r = borrow_global<UsersReward>(@dat3_routel);
        if (simple_mapv1::contains_key(&ueer_r.data, &addr)) {
            let r = simple_mapv1::borrow(&ueer_r.data, &addr);
            _taday_spend = r.taday_spend;
            _total_spend = r.total_spend;
            _earn = r.earn;
            let len = simple_mapv1::length(&r.taday_earn);
            if (len > 0) {
                let i = 0u64;
                while (i < len) {
                    let (_k, _v) = simple_mapv1::find_index(&r.taday_earn, i);
                    vector::push_back(&mut _taday_earn_key, *_k) ;
                    vector::push_back(&mut _taday_earn, *_v) ;
                };
            };

            _dat3 = r.reward + r.reward_claim;
            _every_reward_time = r.every_dat3_reward_time;
            _every_reward = r.every_dat3_reward;
        };
        (_taday_spend, _total_spend, _earn, _dat3, _every_reward_time, _every_reward, _taday_earn_key, _taday_earn)
    }

    //get user charging standard ( discard)
    #[view]
    public fun fee_of_mine(user: address): (u64, u64, u64) acquires FeeStore, MemberStore
    {
        let fee_s = borrow_global<FeeStore>(@dat3_routel);
        let member_store = borrow_global<MemberStore>(@dat3_routel);
        if (simple_mapv1::contains_key(&member_store.member, &user)) {
            let is_me = simple_mapv1::borrow(&member_store.member, &user);
            return (fee_s.chatFee, is_me.mFee, *simple_mapv1::borrow(&fee_s.mFee, &is_me.mFee))
        };
        return (fee_s.chatFee, 1u64, *simple_mapv1::borrow(&fee_s.mFee, &1u64))
    }

    //get all of charging standard
    #[view]
    public fun fee_of_all(): (u64, vector<u64>) acquires FeeStore
    {
        let fee = borrow_global<FeeStore>(@dat3_routel);
        let vl = vector::empty<u64>();
        vector::push_back(&mut vl, *simple_mapv1::borrow(&fee.mFee, &1));
        vector::push_back(&mut vl, *simple_mapv1::borrow(&fee.mFee, &2));
        vector::push_back(&mut vl, *simple_mapv1::borrow(&fee.mFee, &3));
        vector::push_back(&mut vl, *simple_mapv1::borrow(&fee.mFee, &4));
        vector::push_back(&mut vl, *simple_mapv1::borrow(&fee.mFee, &5));
        (fee.chatFee, vl)
    }

    //see fid invite reward
    #[view]
    public fun fid_reward(fid: u64): (u64, u64, u64, u64, vector<address>, u64, ) acquires FidStore
    {
        assert!(exists<FidStore>(@dat3_routel), error::not_found(NOT_FOUND));
        let f = borrow_global<FidStore>(@dat3_routel);
        if (simple_mapv1::contains_key(&f.data, &fid)) {
            let fr = simple_mapv1::borrow(&f.data, &fid);
            return (fr.fid, fr.amount, fr.spend, fr.earn, fr.users, fr.claim)
        };
        return (fid, 0, 0, 0, vector::empty<address>(), 0)
    }

    //Determine whether the current user identity is a receiver or a sender
    #[view]
    public fun is_sender(sender: address, to: address): u64
    acquires DAT3MsgHoder {
        let s = borrow_global<DAT3MsgHoder>(@dat3_routel);
        // if (!simple_mapv1::contains_key(&s.data, &to)) {
        //     return 5u64
        // };
        // if (!simple_mapv1::contains_key(&s.data, &sender)) {
        //     return 4u64
        // };
        let to_init = simple_mapv1::contains_key(&s.data, &to) ;
        let sender_init = simple_mapv1::contains_key(&s.data, &sender) ;
        //Both are not initialized
        if (!to_init && !sender_init) {
            return 5
        };

        if (to_init && !sender_init) {
            return 5
        };
        if (!to_init && sender_init) {
            return 5
        };

        let m1 = simple_mapv1::borrow(&s.data, &sender);
        let m2 = simple_mapv1::borrow(&s.data, &to);
        //is
        if (vector::contains(&m2.senders, &sender)) {
            return 1u64
        };
        //no
        if (vector::contains(&m1.senders, &to)) {
            return 2u64
        };
        //is
        return 3u64
    }

    #[view]
    public fun view_call_1(sender: address, to: address): vector<u64> acquires DAT3MsgHoder {
        let dat3_msg = borrow_global<DAT3MsgHoder>(@dat3_routel);
        if (!simple_mapv1::contains_key(&dat3_msg.data, &to)) {
            return vector::empty<u64>()
        };
        let to_hode = simple_mapv1::borrow(&dat3_msg.data, &to);
        if (!simple_mapv1::contains_key(&to_hode.receive, &sender)) {
            return vector::empty<u64>()
        };
        let receive = simple_mapv1::borrow(&to_hode.receive, &sender);
        return *receive
    }

    #[view]
    public fun remaining_time(req_addr: address): vector<Call>
    acquires CurrentRoom
    {
        let current_room = borrow_global<CurrentRoom>(@dat3_routel);
        if (simple_mapv1::contains_key(&current_room.data, &req_addr)) {
            return *simple_mapv1::borrow(&current_room.data, &req_addr)
        } ;
        return vector::empty<Call>()
    }
}