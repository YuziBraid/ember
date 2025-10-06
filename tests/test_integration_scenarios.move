#[test_only]
module upshift_vaults::test_integration_scenarios {

    use sui::test_scenario;
    use sui::coin;
    use sui::balance;
    use sui::clock;

    use upshift_vaults::admin::{ProtocolConfig, AdminCap};
    use upshift_vaults::test_utils::{Self, USDC, UltraUSDC};
    use upshift_vaults::vault::{Self, Vault};


    #[test]
    fun test_tvl(){
        let protocol_admin = test_utils::protocol_admin();
        let operator = test_utils::bob();

        let mut scenario = test_scenario::begin(protocol_admin);
        test_utils::initialize(&mut scenario);


        test_utils::update_vault_rate<USDC,UltraUSDC>(&mut scenario, 1000000000, 1050000000);

        let deposit_amount = 100000000; // 100 USDC
        let deposit_receipt = test_utils::deposit_assets<USDC, UltraUSDC>(&mut scenario, operator, deposit_amount);

        assert!(coin::value(&deposit_receipt) == 105000000, 0);

        coin::burn_for_testing(deposit_receipt);


        test_scenario::next_tx(&mut scenario, operator);
            let vault = test_scenario::take_shared<Vault<USDC,UltraUSDC>>(&scenario );
            let tvl = vault::get_vault_tvl<USDC,UltraUSDC>(&vault);
            assert!(tvl == 100000000, 2);

            test_scenario::return_shared(vault);

        test_scenario::end(scenario);   
    }

     #[test]
    fun test_tvl_should_decrease_with_rate_change_up(){
        let protocol_admin = test_utils::protocol_admin();
        let operator = test_utils::bob();

        let mut scenario = test_scenario::begin(protocol_admin);
        test_utils::initialize(&mut scenario);

        
        test_utils::update_vault_rate<USDC,UltraUSDC>(&mut scenario, 1000000000, 1010000000);


        let deposit_amount = 100000000; // 100 USDC
        let deposit_receipt = test_utils::deposit_assets<USDC, UltraUSDC>(&mut scenario, operator, deposit_amount);

        assert!(coin::value(&deposit_receipt) == 101000000, 0);

        coin::burn_for_testing(deposit_receipt);


        test_utils::update_vault_rate<USDC,UltraUSDC>(&mut scenario, 2000000000, 1020000000);


        test_scenario::next_tx(&mut scenario, operator);
            let vault = test_scenario::take_shared<Vault<USDC,UltraUSDC>>(&scenario );
            let tvl = vault::get_vault_tvl<USDC,UltraUSDC>(&vault);
            assert!(tvl == 99019607, 2);

            test_scenario::return_shared(vault);

        test_scenario::end(scenario);   
    }

     #[test]
    fun test_tvl_should_increase_with_rate_change_down(){
        let protocol_admin = test_utils::protocol_admin();
        let operator = test_utils::bob();

        let mut scenario = test_scenario::begin(protocol_admin);
        test_utils::initialize(&mut scenario);


        test_utils::update_vault_rate<USDC,UltraUSDC>(&mut scenario, 1000000000, 1010000000);


        let deposit_amount = 100000000; // 100 USDC
        let deposit_receipt = test_utils::deposit_assets<USDC, UltraUSDC>(&mut scenario, operator, deposit_amount);

        assert!(coin::value(&deposit_receipt) == 101000000, 0);

        coin::burn_for_testing(deposit_receipt);


        test_utils::update_vault_rate<USDC,UltraUSDC>(&mut scenario, 2000000000, 990000000);

        test_scenario::next_tx(&mut scenario, operator);
        let vault = test_scenario::take_shared<Vault<USDC,UltraUSDC>>(&scenario );
        assert!(vault::get_vault_rate<USDC, UltraUSDC>(&vault) == 990000000, 1);
        test_scenario::return_shared(vault);


        test_scenario::next_tx(&mut scenario, operator);
            let vault = test_scenario::take_shared<Vault<USDC,UltraUSDC>>(&scenario );
            let tvl = vault::get_vault_tvl<USDC,UltraUSDC>(&vault);
            assert!(tvl == 102020202, 2);

            test_scenario::return_shared(vault);

        test_scenario::end(scenario);   
    }


    #[test]
    fun test_multi_user_deposit_withdraw_cycle() {
        // Complex scenario: Multiple users deposit, rates change, operator withdrawals, fee collection
        
        let protocol_admin = test_utils::protocol_admin();
        let operator = test_utils::bob();
        let alice = test_utils::alice();
        let sub_account = @0xDEAD;
        
        let mut scenario = test_scenario::begin(protocol_admin);
        test_utils::initialize(&mut scenario);
        test_utils::set_sub_account(&mut scenario, sub_account);

        // === Phase 1: Initial deposits ===
        let alice_deposit = 50000000; // 50 USDC
        let alice_receipt = test_utils::deposit_assets<USDC, UltraUSDC>(&mut scenario, alice, alice_deposit);
        
        // Verify initial state
        test_scenario::next_tx(&mut scenario, alice);
        let vault = test_scenario::take_shared<Vault<USDC,UltraUSDC>>(&scenario);
        assert!(vault::get_vault_balance<USDC,UltraUSDC>(&vault) == alice_deposit , 0);
        assert!(coin::value(&alice_receipt) == alice_deposit, 1); // 1:1 at default rate
        test_scenario::return_shared(vault);

        // === Phase 2: Rate changes ===
        test_utils::update_vault_rate<USDC,UltraUSDC>(&mut scenario, 1000000000, 1030000000); // 103%        

        // === Phase 3: More deposits at new rate ===
        let alice_deposit2 = 30000000; // 30 USDC
        let alice_receipt2 = test_utils::deposit_assets<USDC, UltraUSDC>(&mut scenario, alice, alice_deposit2);
        
        // Verify new shares calculation: 30 * 1.03 = 30.9 USDC
        assert!(coin::value(&alice_receipt2) == 30900000, 2);

        // === Phase 4: Operator withdraws to sub-account ===
        let withdrawal_amount = 20000000; // 20 USDC
        test_scenario::next_tx(&mut scenario, operator);
        let config = test_scenario::take_shared<ProtocolConfig>(&scenario);
        let mut vault = test_scenario::take_shared<Vault<USDC,UltraUSDC>>(&scenario);
        
        let vault_balance_before = vault::get_vault_balance<USDC,UltraUSDC>(&vault);
        vault::withdraw_from_vault_without_redeeming_shares(&mut vault, &config, sub_account, withdrawal_amount, test_scenario::ctx(&mut scenario));
        let vault_balance_after = vault::get_vault_balance<USDC,UltraUSDC>(&vault);
        
        assert!(vault_balance_after == vault_balance_before - withdrawal_amount, 3);
        test_scenario::return_shared(config);
        test_scenario::return_shared(vault);

        // === Phase 5: Deposit back to vault ===
        test_scenario::next_tx(&mut scenario, operator);
        let config = test_scenario::take_shared<ProtocolConfig>(&scenario);
        let mut vault = test_scenario::take_shared<Vault<USDC,UltraUSDC>>(&scenario);
        
        let deposit_balance = balance::create_for_testing<USDC>(15000000); // 15 USDC
        vault::deposit_to_vault_without_minting_shares(&mut vault, &config, deposit_balance, sub_account, test_scenario::ctx(&mut scenario));
        
        test_scenario::return_shared(config);
        test_scenario::return_shared(vault);

        // === Phase 6: Fee collection ===
        test_scenario::next_tx(&mut scenario, operator);
        let config = test_scenario::take_shared<ProtocolConfig>(&scenario);
        let mut vault = test_scenario::take_shared<Vault<USDC,UltraUSDC>>(&scenario);
        
        // Add some fees to collect
        vault::increase_platform_fee_accrued<USDC,UltraUSDC>(&mut vault, 1000000, 1000000000); // 1 USDC
        vault::collect_platform_fee(&mut vault, &config, test_scenario::ctx(&mut scenario));
        
        test_scenario::return_shared(config);
        test_scenario::return_shared(vault);

        // === Final verification ===
        test_scenario::next_tx(&mut scenario, alice);
        let vault = test_scenario::take_shared<Vault<USDC,UltraUSDC>>(&scenario);
        let total_shares = vault::get_vault_total_shares_in_circulation<USDC,UltraUSDC>(&vault);
        let expected_total = coin::value(&alice_receipt) + coin::value(&alice_receipt2);
        assert!(total_shares == expected_total, 4);
        test_scenario::return_shared(vault);

        // Cleanup
        coin::burn_for_testing(alice_receipt);
        coin::burn_for_testing(alice_receipt2);
        test_scenario::end(scenario);
    }

    #[test]
    fun test_admin_operations_sequence() {
        // Test comprehensive admin operations in sequence
        
        let protocol_admin = test_utils::protocol_admin();
        let new_admin = test_utils::alice();
        let new_operator = @0x91;
        
        let mut scenario = test_scenario::begin(protocol_admin);
        test_utils::initialize(&mut scenario);
        test_utils::set_vault_rate_manager<USDC,UltraUSDC>(&mut scenario, new_operator);

        // === Change vault admin ===
        test_scenario::next_tx(&mut scenario, protocol_admin);
        let config = test_scenario::take_shared<ProtocolConfig>(&scenario);
        let mut vault = test_scenario::take_shared<Vault<USDC,UltraUSDC>>(&scenario);
        let cap = test_scenario::take_from_address<AdminCap>(&scenario, protocol_admin);
        
        vault::change_vault_admin<USDC,UltraUSDC>(&mut vault, &config, &cap, new_admin);
        assert!(vault::get_vault_admin<USDC,UltraUSDC>(&vault) == new_admin, 0);
        
        test_scenario::return_shared(config);
        test_scenario::return_shared(vault);
        test_scenario::return_to_address<AdminCap>(protocol_admin, cap);

        // === New admin changes operator ===
        test_scenario::next_tx(&mut scenario, new_admin);
        let config = test_scenario::take_shared<ProtocolConfig>(&scenario);
        let mut vault = test_scenario::take_shared<Vault<USDC,UltraUSDC>>(&scenario);
        
        vault::change_vault_operator<USDC,UltraUSDC>(&mut vault, &config, new_operator, test_scenario::ctx(&mut scenario));
        assert!(vault::get_vault_operator<USDC,UltraUSDC>(&vault) == new_operator, 1);
        
        test_scenario::return_shared(config);
        test_scenario::return_shared(vault);

        // === New admin updates fee percentage ===
        test_scenario::next_tx(&mut scenario, new_admin);
        let config = test_scenario::take_shared<ProtocolConfig>(&scenario);
        let mut vault = test_scenario::take_shared<Vault<USDC,UltraUSDC>>(&scenario);
        
        let new_fee = 2000000; // 0.2%
        vault::update_vault_fee_percentage(&mut vault, &config, new_fee, test_scenario::ctx(&mut scenario));
        assert!(vault::get_vault_fee_percentage<USDC,UltraUSDC>(&vault) == new_fee, 2);
        
        test_scenario::return_shared(config);
        test_scenario::return_shared(vault);

        // === The current operator can change the vault rate === 
        test_scenario::next_tx(&mut scenario, new_operator);
        let config = test_scenario::take_shared<ProtocolConfig>(&scenario);
        let mut vault = test_scenario::take_shared<Vault<USDC,UltraUSDC>>(&scenario);
        let mut clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
        clock::set_for_testing(&mut clock, 1000000000);

        vault::update_vault_rate(&mut vault, &config, 1020000000, &clock, test_scenario::ctx(&mut scenario));

        assert!(vault::get_vault_rate<USDC,UltraUSDC>(&vault) == 1020000000, 3);

        test_scenario::return_shared(config);
        test_scenario::return_shared(vault);
        clock::destroy_for_testing(clock);


 
        test_scenario::end(scenario);
    }

    #[test]
    fun test_blacklist_during_operations() {
        // Test blacklisting users during active operations
        
        let protocol_admin = test_utils::protocol_admin();
        let operator = test_utils::bob();
        let alice = test_utils::alice();
        
        let mut scenario = test_scenario::begin(protocol_admin);
        test_utils::initialize(&mut scenario);

        // === Alice makes initial deposit ===
        let deposit_amount = 25000000; // 25 USDC
        let alice_receipt = test_utils::deposit_assets<USDC, UltraUSDC>(&mut scenario, alice, deposit_amount);

        // === Operator blacklists Alice ===
        test_scenario::next_tx(&mut scenario, operator);
        let config = test_scenario::take_shared<ProtocolConfig>(&scenario);
        let mut vault = test_scenario::take_shared<Vault<USDC,UltraUSDC>>(&scenario);
        
        vault::set_blacklisted_account(&mut vault, &config, alice, true, test_scenario::ctx(&mut scenario));
        let blacklisted = vault::get_vault_blacklisted_accounts<USDC,UltraUSDC>(&vault);
        assert!(vector::length(&blacklisted) == 1, 0);
        
        test_scenario::return_shared(config);
        test_scenario::return_shared(vault);

        // === Verify Alice can't make new deposits ===
        // This should fail due to blacklist
        // (We can't test this directly without expected_failure, but we've tested it in blacklist tests)

        // === Operator removes Alice from blacklist ===
        test_scenario::next_tx(&mut scenario, operator);
        let config = test_scenario::take_shared<ProtocolConfig>(&scenario);
        let mut vault = test_scenario::take_shared<Vault<USDC,UltraUSDC>>(&scenario);
        
        vault::set_blacklisted_account(&mut vault, &config, alice, false, test_scenario::ctx(&mut scenario));
        let blacklisted = vault::get_vault_blacklisted_accounts<USDC,UltraUSDC>(&vault);
        assert!(vector::length(&blacklisted) == 0, 1);
        
        test_scenario::return_shared(config);
        test_scenario::return_shared(vault);

        // === Alice can deposit again ===
        let alice_receipt2 = test_utils::deposit_assets<USDC, UltraUSDC>(&mut scenario, alice, deposit_amount);
        assert!(coin::value(&alice_receipt2) > 0, 2);

        coin::burn_for_testing(alice_receipt);
        coin::burn_for_testing(alice_receipt2);
        test_scenario::end(scenario);
    }

    #[test]
    fun test_vault_pause_operations() {
        // Test vault pause/unpause functionality
        
        let protocol_admin = test_utils::protocol_admin();
        let alice = test_utils::alice();
        
        let mut scenario = test_scenario::begin(protocol_admin);
        test_utils::initialize(&mut scenario);

        // === Initial deposit works ===
        let deposit_amount = 10000000; // 10 USDC  
        let alice_receipt = test_utils::deposit_assets<USDC, UltraUSDC>(&mut scenario, alice, deposit_amount);

        // === Admin pauses vault ===
        test_scenario::next_tx(&mut scenario, protocol_admin);
        let config = test_scenario::take_shared<ProtocolConfig>(&scenario);
        let mut vault = test_scenario::take_shared<Vault<USDC,UltraUSDC>>(&scenario);
        
        vault::set_vault_paused_status(&mut vault, &config, true, test_scenario::ctx(&mut scenario));
        assert!(vault::get_vault_paused<USDC,UltraUSDC>(&vault) == true, 0);
        
        test_scenario::return_shared(config);
        test_scenario::return_shared(vault);

        // === Deposits should fail when paused (tested in deposit tests) ===

        // === Admin unpauses vault ===
        test_scenario::next_tx(&mut scenario, protocol_admin);
        let config = test_scenario::take_shared<ProtocolConfig>(&scenario);
        let mut vault = test_scenario::take_shared<Vault<USDC,UltraUSDC>>(&scenario);
        
        vault::set_vault_paused_status(&mut vault, &config, false, test_scenario::ctx(&mut scenario));
        assert!(vault::get_vault_paused<USDC,UltraUSDC>(&vault) == false, 1);
        
        test_scenario::return_shared(config);
        test_scenario::return_shared(vault);

        // === Deposits work again ===
        let alice_receipt2 = test_utils::deposit_assets<USDC, UltraUSDC>(&mut scenario, alice, deposit_amount);
        assert!(coin::value(&alice_receipt2) > 0, 2);

        coin::burn_for_testing(alice_receipt);
        coin::burn_for_testing(alice_receipt2);
        test_scenario::end(scenario);
    }

    #[test]
    fun test_rate_change_limits_integration() {
        // Test rate change limits in realistic scenarios
        
        let protocol_admin = test_utils::protocol_admin();
        
        let mut scenario = test_scenario::begin(protocol_admin);
        test_utils::initialize(&mut scenario);

        // === Test maximum allowed rate change (5%) ===
        test_utils::update_vault_rate<USDC,UltraUSDC>(&mut scenario, 1000000000, 1050000000);
        
        // === Test another 5% change from new base ===        
        let next_increase = 1102500000; // 110.25% (5% increase from 105%)
        test_utils::update_vault_rate<USDC,UltraUSDC>(&mut scenario, 2000000000, next_increase);


        // === Test decreasing rate ===        
        let decrease_rate = 1047375000; // ~95% of current rate (5% decrease)
        test_utils::update_vault_rate<USDC,UltraUSDC>(&mut scenario, 3000000000, decrease_rate);

        test_scenario::end(scenario);
    }

    #[test]
    fun test_fee_accumulation_and_collection() {
        // Test fee accumulation over multiple operations
        
        let protocol_admin = test_utils::protocol_admin();
        let operator = test_utils::bob();
        
        let mut scenario = test_scenario::begin(protocol_admin);
        test_utils::initialize(&mut scenario);

        // === Add platform fees ===
        test_scenario::next_tx(&mut scenario, operator);
        let config = test_scenario::take_shared<ProtocolConfig>(&scenario);
        let mut vault = test_scenario::take_shared<Vault<USDC,UltraUSDC>>(&scenario);
        
        vault::increase_platform_fee_accrued<USDC,UltraUSDC>(&mut vault, 5000000, 1000000000); // 5 USDC
        assert!(vault::get_accrued_platform_fee<USDC,UltraUSDC>(&vault) == 5000000, 0);
        
        test_scenario::return_shared(config);
        test_scenario::return_shared(vault);

        // === Add more fees ===
        test_scenario::next_tx(&mut scenario, operator);
        let config = test_scenario::take_shared<ProtocolConfig>(&scenario);
        let mut vault = test_scenario::take_shared<Vault<USDC,UltraUSDC>>(&scenario);
        
        vault::increase_platform_fee_accrued<USDC,UltraUSDC>(&mut vault, 3000000, 1000000000); // 3 USDC
        assert!(vault::get_accrued_platform_fee<USDC,UltraUSDC>(&vault) == 8000000, 1);
        
        test_scenario::return_shared(config);
        test_scenario::return_shared(vault);

        // === Collect all fees ===
        test_scenario::next_tx(&mut scenario, operator);
        let config = test_scenario::take_shared<ProtocolConfig>(&scenario);
        let mut vault = test_scenario::take_shared<Vault<USDC,UltraUSDC>>(&scenario);
        
        vault::collect_platform_fee(&mut vault, &config, test_scenario::ctx(&mut scenario));
        assert!(vault::get_accrued_platform_fee<USDC,UltraUSDC>(&vault) == 0, 2);
        
        test_scenario::return_shared(config);
        test_scenario::return_shared(vault);

        test_scenario::end(scenario);
    }
}