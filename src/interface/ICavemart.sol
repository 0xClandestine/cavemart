// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

interface ICavemart {
//////////////////////////////////////////////////////////////////////
    // USER ACTIONS
    //////////////////////////////////////////////////////////////////////

    // @notice              Struct containing metadata for a ERC721 <-> ERC20 trade.
    //
    // @param seller        The address of the account that wants to sell their 
    //                      'erc721' in exchange for 'price' denominated in 'erc20'.
    //
    // @param erc721        The address of a contract that follows the ERC-721 standard,
    //                      also the address of the collection that holds the token that 
    //                      you're purchasing.
    //
    // @param erc20         The address of a contract that follows the ERC-20 standard,
    //                      also the address of the token that the seller wants in exchange
    //                      for their 'erc721'
    //
    // @dev                 If 'erc20' is equal to address(0), we assume the seller wants
    //                      native ETH in exchange for their 'erc721'.
    //
    // @param tokenId       The 'erc721' token identification number, 'tokenId'.
    //
    // @param startPrice    The starting or fixed price the offered 'erc721' is being sold for, 
    //                      if ZERO we assume the 'seller' is hosting a dutch auction.
    //
    // @dev                 If a 'endPrice' and 'start' time are both defined, we assume
    //                      the order type is a dutch auction. So 'startPrice' would be
    //                      the price the auction starts at, otherwise 'startPrice' is
    //                      the fixed cost the 'seller' is charging.
    //
    // @param endPrice      The 'endPrice' is the price in which a dutch auction would no
    //                      no longer be valid after.
    //
    // @param start         The time in which the dutch auction starts, if ZERO we assume 
    //                      the 'seller' is hosting a dutch auction.
    //
    // @param deadline      The time in which the signature/swap is not valid after.
    struct SwapMetadata {
        address seller;
        address erc721;
        address erc20;
        uint256 tokenId;
        uint256 startPrice;
        uint256 endPrice;
        uint256 start;
        uint256 deadline;
    }

    function computeSigner(
        SwapMetadata calldata data,
        uint256 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (address signer);

    function DOMAIN_SEPARATOR() external returns (bytes32);
    function computePrice(
        SwapMetadata calldata data
    ) external returns (uint256 price);

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
    ) external payable;
    //////////////////////////////////////////////////////////////////////
    // MANAGMENT EVENTS
    //////////////////////////////////////////////////////////////////////

    // @notice emitted when 'feeAddress' is updated.
    event FeeAddressUpdated(
        address newFeeAddress
    );
    
    // @notice emitted when 'collectionFee' for 'collection' is updated.
    event CollectionFeeUpdated(
        address collection, 
        uint256 percent
    );
    
    // @notice emitted when 'allowed' for a 'token' has been updated.
    event WhitelistUpdated(
        address token,
        bool whitelisted
    );

    // @notice emitted when ETH from fees is collected from the contract.
    event FeeCollection(
        address token,
        uint256 amount
    );

    event OrderExecuted(
        address indexed seller,
        address indexed erc721,
        address indexed erc20,
        uint256 tokenId,
        uint256 price,
        uint256 deadline
    );
}