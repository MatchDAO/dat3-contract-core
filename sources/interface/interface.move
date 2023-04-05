module dat3::interface {
    use dat3::routel;

    public fun to_reward(admin: &signer) {
        routel::to_reward(admin);
    }

    public fun user_position(user: address): (u64, u64, u64, u64, u64, u64, u64, u64, u64, u64) {
        let (_uid, _fid, _mFee, _apt, _dat3, _amount, _reward, _claim, _taday_spend, _total_spend) = routel::assets(
            user
        );
        return (_uid, _fid, _mFee, _apt, _dat3, _amount, _reward, _claim, _taday_spend, _total_spend)
    }
}