// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import {Script} from "forge-std/Script.sol";
import {IRouterClient} from "@ccip/contracts/interfaces/IRouterClient.sol";
import {Client} from "@ccip/contracts/libraries/Client.sol";
import {IERC20} from "@openzeppelin/contracts@4.8.3/token/ERC20/IERC20.sol";

contract BridgeTokensScript is Script {
    function setUp() public {}

    function run(
        address receiverAddress,
        uint64 destinationChainSelector,
        address tokenToSendAddress,
        uint256 amountToSend,
        address linkTokenAddress,
        address routerAddress
    ) public {
        Client.EVMTokenAmount[] memory tokenAmount = new Client.EVMTokenAmount[](1);
        tokenAmount[0] = Client.EVMTokenAmount({token: tokenToSendAddress, amount: amountToSend});
        vm.startBroadcast();
        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(receiverAddress),
            data: "",
            tokenAmounts: tokenAmount,
            feeToken: linkTokenAddress,
            extraArgs: Client._argsToBytes(Client.EVMExtraArgsV1({gasLimit: 500_000}))
        });
        uint256 ccipFee = IRouterClient(routerAddress).getFee(destinationChainSelector, message);
        IERC20(linkTokenAddress).approve(routerAddress, ccipFee);
        IERC20(tokenToSendAddress).approve(routerAddress, amountToSend);
        IRouterClient(routerAddress).ccipSend(destinationChainSelector, message);
        vm.stopBroadcast();
    }
}
