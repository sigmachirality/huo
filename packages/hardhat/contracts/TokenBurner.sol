pragma solidity >=0.8.0 <0.9.0;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";

contract TokenBurner is VRFConsumerBaseV2 {
  address private constant ROLL_IN_PROGRESS = address(60420);
  enum BurnType { Ether, Token, NFT }

  struct BurnIntent {
    uint256 requestId;
    BurnType burnType;
    uint256 amount;
    IERC20 token;
    IERC721 nft;
  }
  
  uint64 private _subscriptionID;
  bytes32 private _keyHash = 0x474e34a077df58807dbe9c96d3c009b23b3c6d0cce433e59bbf5b34f823bc56c;
  address _contractOwner;
  VRFCoordinatorV2Interface COORDINATOR;
  
  uint32 numWords = 1;
  uint32 callbackGasLimit = 40000;
  uint16 requestConfirmations = 3;

  mapping(uint256 => address) private burners;
  mapping(uint256 => address) private results;
  mapping(uint256 => BurnIntent) private intents;

  event AssetBurnRequested(uint256 indexed requestId, address indexed burner);
  event AssetBurned(uint256 indexed requestId, address indexed result);

  constructor(uint64 subscriptionId, address vrfCoordinator) VRFConsumerBaseV2(vrfCoordinator) {
    COORDINATOR = VRFCoordinatorV2Interface(vrfCoordinator);
    _contractOwner = msg.sender;
    _subscriptionID = subscriptionId;
  }

  function requestAddress(address burner) private returns (uint256 requestId) {
      requestId = COORDINATOR.requestRandomWords(
        _keyHash,
        _subscriptionID,
        requestConfirmations,
        callbackGasLimit,
        numWords
      );

      burners[requestId] = burner;
      results[requestId] = ROLL_IN_PROGRESS;
      emit AssetBurnRequested(requestId, burner);
  }

  function burnEther(address burner, uint256 value) public returns (uint256 requestId) {
    requestId = requestAddress(burner);
    BurnIntent memory intent;
    intent.requestId = requestId;
    intent.burnType = BurnType.Ether;
    intent.amount = value;
    intents[requestId] = intent;
  }

  function burnToken(address burner, IERC20 token, uint256 value) public returns (uint256 requestId) {
    requestId = requestAddress(burner);
    BurnIntent memory intent;
    intent.requestId = requestId;
    intent.burnType = BurnType.Token;
    intent.amount = value;
    intent.token = token;
    intents[requestId] = intent;
  }

  function burnNFT(address burner, IERC721 nft) public returns (uint256 requestId) {
    requestId = requestAddress(burner);
    BurnIntent memory intent;
    intent.requestId = requestId;
    intent.burnType = BurnType.NFT;
    intent.nft = nft;
    intents[requestId] = intent;
  }

  function fulfillRandomWords(uint256 requestId, uint256[] memory randomWords) internal override {
    address burnTarget = address(uint160(randomWords[0]));
    BurnIntent memory intent = intents[requestId];
    address burner = burners[requestId];
    results[requestId] = burnTarget;

    if (intent.burnType == BurnType.Ether) {
      payable(burnTarget).call{value: intent.amount }("");
      emit AssetBurned(requestId, burnTarget);
    } else if (intent.burnType == BurnType.Token) {
      intent.token.transferFrom(burner, burnTarget, intent.amount);
      emit AssetBurned(requestId, burnTarget);
    } else if (intent.burnType == BurnType.NFT) {
      intent.nft.transferFrom(burner, burnTarget, intent.amount);
      emit AssetBurned(requestId, burnTarget);
    }
    delete intents[requestId];
  }

}