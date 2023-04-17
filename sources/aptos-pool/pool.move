module dat3::pool {
    use std::error;
    use std::signer;
    use aptos_framework::account::{Self, SignerCapability};
    use aptos_framework::coin::{Self, Coin};
    use dat3::dat3_coin::DAT3;
    friend dat3::routel;
    friend dat3::interface;

    struct Pool has key {
        coins: Coin<0x1::aptos_coin::AptosCoin>,
    }

    struct RewardPool  has key { last: u64, coins: Coin<DAT3>, }

    struct SignerCapabilityStore has key, store {
        sinCap: SignerCapability,
    }

    const PERMISSION_DENIED: u64 = 1000;
    const ALREADY_EXISTS: u64 = 112;

    /********************/
    /* ENTRY FUNCTIONS */
    /********************/
    public entry fun init_pool(owner: &signer)
    {
        let addr = signer::address_of(owner);
        assert!(addr == @dat3, error::permission_denied(PERMISSION_DENIED));
        assert!(!exists<Pool>(@dat3_pool), error::already_exists(ALREADY_EXISTS));
        let (resourceSigner, sinCap) = account::create_resource_account(owner, b"dat3_pool_v1");
        move_to(&resourceSigner, SignerCapabilityStore {
            sinCap
        });

        move_to(&resourceSigner, Pool {
            coins: coin::zero<0x1::aptos_coin::AptosCoin>(),
        });
        if (!exists<RewardPool>(addr)) {
            move_to(&resourceSigner, RewardPool {
                last: 0,
                coins: coin::zero<DAT3>(),
            });
        };
    }

    // deposit token
    public entry fun deposit(account: &signer, amount: u64) acquires Pool
    {
        let your_coin = coin::withdraw<0x1::aptos_coin::AptosCoin>(account, amount);
        let a_pool = borrow_global_mut<Pool>(@dat3_pool);
        coin::merge(&mut a_pool.coins, your_coin);
    }

    public entry fun deposit_reward(account: &signer, amount: u64) acquires RewardPool
    {
        let your_coin = coin::withdraw<DAT3>(account, amount);
        let r_pool = borrow_global_mut<RewardPool>(@dat3_pool);
        coin::merge(&mut r_pool.coins, your_coin);
    }


    public fun deposit_reward_coin(coins: Coin<DAT3>) acquires RewardPool
    {
        let r_pool = borrow_global_mut<RewardPool>(@dat3_pool);
        r_pool.last = coin::value<DAT3>(&coins);
        coin::merge(&mut r_pool.coins, coins);
    }

    #[view]
    public fun withdraw_reward_last(): u64 acquires RewardPool
    {
        borrow_global<RewardPool>(@dat3_pool).last
    }

    /********************/
    /* FRIEND FUNCTIONS */
    /********************/


    //Is it safe? yes!
    public(friend) fun withdraw(to: address, amount: u64) acquires Pool
    {
        let a_pool = borrow_global_mut<Pool>(@dat3_pool);
        coin::deposit<0x1::aptos_coin::AptosCoin>(to, coin::extract(&mut a_pool.coins, amount));
    }
    //Withdraw coin,the coins must have attribution
    public(friend) fun withdraw_coin(amount: u64): Coin<0x1::aptos_coin::AptosCoin> acquires Pool
    {
        let a_pool = borrow_global_mut<Pool>(@dat3_pool);
        return coin::extract<0x1::aptos_coin::AptosCoin>(&mut a_pool.coins, amount)
    }

    // no &signer is right
    public(friend) fun withdraw_reward(to: address, amount: u64) acquires RewardPool
    {
        let r_pool = borrow_global_mut<RewardPool>(@dat3_pool);
        coin::deposit<DAT3>(to, coin::extract(&mut r_pool.coins, amount));
    }
}