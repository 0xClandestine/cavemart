// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import {FullMath}               from "./FullMath.sol";
import {SafeTransferLib, ERC20} from "lib/solmate/src/utils/SafeTransferLib.sol";
import {IERC721}                from "lib/openzeppelin-contracts/contracts/token/ERC721/IERC721.sol";
import {ICavemart}            from "./interface/ICavemart.sol";
// TODO add ERC721-holder logic

// @notice              Allows a buyer to execute an order given they've got
//                      an secp256k1 signature from a seller containing verifiable
//                      metadata about the trade. The seller can accept native ETH
//                      or an ERC-20 if they're whitelisted.
//
// @author              Dionysus @ConcaveFi
contract Cavemart is ICavemart {
	// @dev This function ensures this contract can receive ETH
	receive() external payable {}

    //////////////////////////////////////////////////////////////////////
    // IMMUTABLE STORAGE
    //////////////////////////////////////////////////////////////////////

    uint256 internal constant FEE_DIVISOR = 1e4;

    uint256 internal immutable INITIAL_CHAIN_ID;

    bytes32 internal immutable INITIAL_DOMAIN_SEPARATOR;

    // keccak256("Swap(address seller,address erc721,address erc20,uint256 tokenId,uint256 startPrice,uint256 endPrice,uint256 nonce,uint256 start,uint256 deadline)")
    bytes32 public constant SWAP_TYPEHASH = 0x8bca9397be6761f8836a3f24b102db891d663d3e2e89a7c7eea2479c3431068b;

    //////////////////////////////////////////////////////////////////////
    // MUTABLE STORAGE
    //////////////////////////////////////////////////////////////////////

    // @notice Returns the address fees are sent to.
    address payable public feeAddress = payable(msg.sender);

    // @notice Returns the fee charged for selling a token from specific 'collection'
    mapping(address => uint256) public collectionFee;

    // @notice Returns whether a token is allowed to be traded within this contract.
    mapping(address => bool) public allowed;

    // @notice Returns the current nonce of a specific address.
    mapping(address => uint256) public nonces;

    //////////////////////////////////////////////////////////////////////
    // CONSTRUCTION
    //////////////////////////////////////////////////////////////////////

    constructor() {
        INITIAL_CHAIN_ID = block.chainid;
        INITIAL_DOMAIN_SEPARATOR = computeDomainSeparator();
    }

    //////////////////////////////////////////////////////////////////////
    // USER ACTION EVENTS
    //////////////////////////////////////////////////////////////////////
    
    //////////////////////////////////////////////////////////////////////
    // EIP-712 LOGIC
    //////////////////////////////////////////////////////////////////////

    function computeSigner(
        SwapMetadata calldata data,
        uint256 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public virtual view override returns (address signer) {
        
        bytes32 hash = keccak256(
            abi.encode(
                SWAP_TYPEHASH, 
                data.seller, 
                data.erc721, 
                data.erc20, 
                data.tokenId, 
                data.startPrice,
                data.endPrice, 
                nonce,
                data.start, 
                data.deadline
            )
        );
        
        signer = ecrecover(keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR(), hash)), v, r, s);
    }

    function DOMAIN_SEPARATOR() public virtual view override returns (bytes32) {
        return block.chainid == INITIAL_CHAIN_ID ? INITIAL_DOMAIN_SEPARATOR : computeDomainSeparator();
    }

    function computeDomainSeparator() internal view returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                    keccak256(bytes("Fixed Order Market")),
                    keccak256("1"),
                    block.chainid,
                    address(this)
                )
            );
    }

    //////////////////////////////////////////////////////////////////////
    // PRICE LOGIC
    //////////////////////////////////////////////////////////////////////

    function computePrice(
        SwapMetadata calldata data
    ) public virtual view override returns (uint256 price) {

        data.endPrice == 0 || data.start == 0 ? 
            price = data.startPrice : 
            price = data.startPrice - FullMath.mulDiv(
                data.startPrice - data.endPrice, 
                block.timestamp - data.start, 
                data.deadline - data.start
            );
    }

    // @notice              Allows a buyer to execute an order given they've got
    //                      an secp256k1 signature from a seller containing verifiable
    //                      swap metadata.
    //
    // @param data          Struct containing metadata for a ERC721 <-> ERC20 trade.
    //
    // @param v             v is part of a valid secp256k1 signature from the seller.
    //
    // @param r             r is part of a valid secp256k1 signature from the seller.
    //
    // @param s             s is part of a valid secp256k1 signature from the seller.
    function swap(
        SwapMetadata calldata data,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external virtual override payable {

        // Make sure both the 'erc721' and the 'erc20' wanted in exchange are both allowed.
        require(allowed[data.erc721] && allowed[data.erc20], "tokenNotWhitelisted()");

        // Make sure the deadline the 'seller' has specified has not elapsed.
        require(data.deadline >= block.timestamp, "orderExpired()");

        address signer = computeSigner(data, nonces[data.seller]++, v, r, s);

        // Make sure the recovered address is not NULL, and is equal to the 'seller'.
        require(signer != address(0) && signer == data.seller, "signatureInvalid()");
        
        uint256 price = computePrice(data);

        // Cache the fee that's going to be charged to the 'seller'.
        uint256 fee = FullMath.mulDiv(price, collectionFee[data.erc721], FEE_DIVISOR);

        // If 'erc20' is NULL, we assume the seller wants native ETH.
        if (data.erc20 == address(0)) {

            // Make sure the amount of ETH sent is at least the price specified.
            require(msg.value >= price, "insufficientMsgValue()");

            // Transfer msg.value minus 'fee' from this contract to 'seller'
            SafeTransferLib.safeTransferETH(signer, price - fee);

        // If 'erc20' is not NULL, we assume the seller wants a ERC20.
        } else {

            // Transfer 'erc20' 'price' minus 'fee' from caller to 'seller'.
            SafeTransferLib.safeTransferFrom(ERC20(data.erc20), msg.sender, signer, price - fee);
            
            // Transfer 'fee' to 'feeAddress'.
            SafeTransferLib.safeTransferFrom(ERC20(data.erc20), msg.sender, feeAddress, fee);
        }

        // Transfer 'erc721' from 'seller' to msg.sender/caller.
        IERC721(data.erc721).safeTransferFrom(signer, msg.sender, data.tokenId);

        // Emit event since state was mutated.
        emit OrderExecuted(signer, data.erc721, data.erc20, data.tokenId, price, data.deadline);
    }
    
    //////////////////////////////////////////////////////////////////////
    // MANAGMENT MODIFIERS
    //////////////////////////////////////////////////////////////////////

    // @notice only allows 'feeAddress' to call modified function.
    modifier access() {
        require(msg.sender == feeAddress, "ACCESS");
        _;
    }

    //////////////////////////////////////////////////////////////////////
    // MANAGMENT ACTIONS
    //////////////////////////////////////////////////////////////////////

    function updateFeeAddress(address payable account) external virtual access {
        feeAddress = account;
        emit FeeAddressUpdated(account);
    }

    function updateCollectionFee(address collection, uint256 percent) external virtual access {
        collectionFee[collection] = percent;
        emit CollectionFeeUpdated(collection, percent);
    }

    function updateWhitelist(address token) external virtual access {
        bool whitelisted = !allowed[token];
        allowed[token] = whitelisted;
        emit WhitelistUpdated(token, whitelisted);
    }

    function collectEther() external virtual access {
        uint256 balance = address(this).balance;
        SafeTransferLib.safeTransferETH(feeAddress, balance);
        emit FeeCollection(address(0), balance);
    }

    function collectERC20(address token) external virtual access {
        uint256 balance = ERC20(token).balanceOf(address(this));
        SafeTransferLib.safeTransfer(ERC20(token), feeAddress, balance);
        emit FeeCollection(token, balance);
    }

    //////////////////////////////////////////////////////////////////////
    // EXTERNAL SIGNATURE VERIFICATION LOGIC
    //////////////////////////////////////////////////////////////////////

    // TODO 

    function verify(
        SwapMetadata calldata data,
        address buyer,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external virtual view returns (bool valid) {
        
        // make sure users have approvals as well

        // Make sure current time is greater than 'start' if order type is dutch auction. 
        if (data.start == 0 || data.endPrice == 0) {
            if (data.start > block.timestamp) return false;
        }

        // Make sure both the 'erc721' and the 'erc20' wanted in exchange are both allowed.
        if (!allowed[data.erc721] || !allowed[data.erc20]) return false;

        // Make sure the deadline the 'seller' has specified has not elapsed.
        if (data.deadline < block.timestamp) return false;

        // Make sure the 'seller' still owns the 'erc721' being offered.
        if (IERC721(data.erc721).ownerOf(data.tokenId) != data.seller) return false;

        // Make sure the buyer has 'price' denominated in 'erc20' if 'erc20' is not native ETH.
        if (data.erc20 != address(0)) {
            if (ERC20(data.erc20).balanceOf(buyer) < computePrice(data) && buyer != address(0)) return false;
        }

        address signer = computeSigner(data, nonces[data.seller], v, r, s);

        // Make sure the recovered address is not NULL, and is equal to the 'seller'.
        if (signer == address(0) || signer != data.seller) return false;

        return true;
    }
}