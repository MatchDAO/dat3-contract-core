module dat3::interface {
    use dat3::reward;

    public fun to_reward(admin: &signer) {
        reward::to_reward(admin);
    }


}