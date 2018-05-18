pragma solidity ^0.4.23;


/// @title SafeMath
/// @dev Math operations with safety checks that throw on error
library SafeMath {

    /// @dev Multiplies two numbers, throws on overflow.
    function mul(uint256 a, uint256 b) internal pure returns (uint256 c) {
        if (a == 0) {
            return 0;
        }
        c = a * b;
        assert(c / a == b);
        return c;
    }

    /// @dev Integer division of two numbers, truncating the quotient.
    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        // assert(b > 0); // Solidity automatically throws when dividing by 0
        // uint256 c = a / b;
        // assert(a == b * c + a % b); // There is no case in which this doesn't hold
        return a / b;
    }

    /// @dev Subtracts two numbers, throws on overflow (i.e. if subtrahend is greater than minuend).
    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        assert(b <= a);
        return a - b;
    }

    /// @dev Adds two numbers, throws on overflow.
    function add(uint256 a, uint256 b) internal pure returns (uint256 c) {
        c = a + b;
        assert(c >= a);
        return c;
    }
}


/// @title AddressUtils
/// @dev Utility library of inline functions on addresses
library AddressUtils {

    /// @dev Returns whether the target address is a contract
    /// @param addr address to check
    /// @return whether the target address is a contract
    function isContract(address addr) internal view returns (bool) {
        uint256 size;
        // XXX Currently there is no better way to check if there is a contract in an address
        // than to check the size of the code at that address.
        // See https://ethereum.stackexchange.com/a/14016/36603
        // for more details about how this works.
        // TODO Check this again before the Serenity release, because all addresses will be
        // contracts then.
        // solium-disable-next-line security/no-inline-assembly
        assembly { size := extcodesize(addr) }
        return size > 0;
    }
}


/// @title ERC721 Non-Fungible Token Standard interface
/// @dev see https://github.com/ethereum/EIPs/blob/master/EIPS/eip-721.md
interface ERC721Standard {
    event Transfer(address indexed _from, address indexed _to, uint256 _tokenId);
    event Approval(address indexed _owner, address indexed _approved, uint256 _tokenId);
    event ApprovalForAll(address indexed _owner, address indexed _operator, bool _approved);
    
    function balanceOf(address _owner) external view returns (uint256 _balance);
    function ownerOf(uint256 _tokenId) external view returns (address _owner);

    function safeTransferFrom(address _from, address _to, uint256 _tokenId) external payable;
    function safeTransferFrom(address _from, address _to, uint256 _tokenId, bytes _data) external payable;
    function transferFrom(address _from, address _to, uint256 _tokenId) external payable;

    function approve(address _to, uint256 _tokenId) external payable;
    function setApprovalForAll(address _operator, bool _approved) external;
    function getApproved(uint256 _tokenId) external view returns (address);
    function isApprovedForAll(address _owner, address _operator) external view returns (bool);
}

    
interface ERC721TokenReceiver is ERC721Standard {
    function onERC721Received(address _from, uint256 _tokenId, bytes data) external returns(bytes4);
}


interface ERC721Metadata is ERC721Standard {
    function name() external view returns (string _name);
    function symbol() external view returns (string _symbol);
    function tokenURI(uint256 _tokenId) external view returns (string);
}


interface ERC721Enumerable is ERC721Standard {
    function totalSupply() external view returns (uint256);
    function tokenOfOwnerByIndex(address _owner, uint256 _index) external view returns (uint256 _tokenId);
    function tokenByIndex(uint256 _index) external view returns (uint256);
}


interface ERC721Supplemental is ERC721Standard {
    function exists(uint256 _tokenId) external view returns (bool);
}


interface ERC721 is ERC721Standard, ERC721TokenReceiver, ERC721Enumerable, ERC721Supplemental {
}


/// @title ERC721 Non-Fungible Token Standard basic implementation
/// @dev see https://github.com/ethereum/EIPs/blob/master/EIPS/eip-721.md
contract ERC721Token is ERC721 {
    using SafeMath for uint256;
    using AddressUtils for address;

    // Equals to `bytes4(keccak256("onERC721Received(address,uint256,bytes)"))`
    // which can be also obtained as `ERC721Receiver(0).onERC721Received.selector`
    bytes4 constant ERC721_RECEIVED = 0xf0b9e5ba;

    // Token name
    string internal name_;

    // Token symbol
    string internal symbol_;

    // Array with all token IDs, used for enumeration
    uint256[] internal allTokens;

    // Mapping from token ID to position in the allTokens array
    mapping (uint256 => uint256) internal allTokensIndex;

    // Mapping from token ID to owner
    mapping (uint256 => address) internal tokenOwner;

    // Mapping from owner to list of owned token IDs
    mapping (address => uint256[]) internal ownedTokens;

    // Mapping from token ID to index of the owner tokens list
    mapping (uint256 => uint256) internal ownedTokensIndex;

    // Mapping from owner to number of owned token
    mapping (address => uint256) internal ownedTokensCount;

    // Mapping from token ID to approved address
    mapping (uint256 => address) internal tokenApprovals;

    // Mapping from owner to operator approvals
    mapping (address => mapping (address => bool)) internal operatorApprovals;

    // Optional mapping for token URIs
    mapping (uint256 => string) internal tokenURIs;    

    /// @dev Guarantees msg.sender is owner of the given token
    /// @param _tokenId uint256 ID of the token to validate its ownership belongs to msg.sender
    modifier onlyOwnerOf(uint256 _tokenId) {
        require(ownerOf(_tokenId) == msg.sender);
        _;
    }

    /// @dev Checks msg.sender can transfer a token, by being owner, approved, or operator
    /// @param _tokenId uint256 ID of the token to validate
    modifier canTransfer(uint256 _tokenId) {
        require(isApprovedOrOwner(msg.sender, _tokenId));
        _;
    }

    /// @dev Constructor function
    constructor(string _name, string _symbol) public {
        name_ = _name;
        symbol_ = _symbol;
    }

    /// @dev Gets the balance of the specified address
    /// @param _owner address to query the balance of
    /// @return uint256 representing the amount owned by the passed address
    function balanceOf(address _owner) public view returns (uint256) {
        require(_owner != address(0));
        return ownedTokensCount[_owner];
    }

    /// @dev Gets the owner of the specified token ID
    /// @param _tokenId uint256 ID of the token to query the owner of
    /// @return owner address currently marked as the owner of the given token ID
    function ownerOf(uint256 _tokenId) public view returns (address) {
        address owner = tokenOwner[_tokenId];
        require(owner != address(0));
        return owner;
    }

    /// @dev Safely transfers the ownership of a given token ID to another address
    /// @dev If the target address is a contract, it must implement `onERC721Received`,
    ///  which is called upon a safe transfer, and return the magic value
    ///  `bytes4(keccak256("onERC721Received(address,uint256,bytes)"))`; otherwise,
    ///  the transfer is reverted.
    /// @dev Requires the msg sender to be the owner, approved, or operator
    /// @param _from current owner of the token
    /// @param _to address to receive the ownership of the given token ID
    /// @param _tokenId uint256 ID of the token to be transferred
    function safeTransferFrom(address _from, address _to, uint256 _tokenId) public canTransfer(_tokenId) {
        // solium-disable-next-line arg-overflow
        safeTransferFrom(_from, _to, _tokenId, "");
    }

    /// @dev Safely transfers the ownership of a given token ID to another address
    /// @dev If the target address is a contract, it must implement `onERC721Received`,
    ///  which is called upon a safe transfer, and return the magic value
    ///  `bytes4(keccak256("onERC721Received(address,uint256,bytes)"))`; otherwise,
    ///  the transfer is reverted.
    /// @dev Requires the msg sender to be the owner, approved, or operator
    /// @param _from current owner of the token
    /// @param _to address to receive the ownership of the given token ID
    /// @param _tokenId uint256 ID of the token to be transferred
    /// @param _data bytes data to send along with a safe transfer check
    function safeTransferFrom(address _from, address _to, uint256 _tokenId, bytes _data) public canTransfer(_tokenId) {
        transferFrom(_from, _to, _tokenId);
        // solium-disable-next-line arg-overflow
        require(checkAndCallSafeTransfer(_from, _to, _tokenId, _data));
    }

    /// @dev Transfers the ownership of a given token ID to another address
    /// @dev Usage of this method is discouraged, use `safeTransferFrom` whenever possible
    /// @dev Requires the msg sender to be the owner, approved, or operator
    /// @param _from current owner of the token
    /// @param _to address to receive the ownership of the given token ID
    /// @param _tokenId uint256 ID of the token to be transferred
    function transferFrom(address _from, address _to, uint256 _tokenId) public canTransfer(_tokenId) {
        require(_from != address(0));
        require(_to != address(0));

        clearApproval(_from, _tokenId);
        removeTokenFrom(_from, _tokenId);
        addTokenTo(_to, _tokenId);

        emit Transfer(_from, _to, _tokenId);
    }

    /// @dev Approves another address to transfer the given token ID
    /// @dev The zero address indicates there is no approved address.
    /// @dev There can only be one approved address per token at a given time.
    /// @dev Can only be called by the token owner or an approved operator.
    /// @param _to address to be approved for the given token ID
    /// @param _tokenId uint256 ID of the token to be approved
    function approve(address _to, uint256 _tokenId) public {
        address owner = ownerOf(_tokenId);
        require(_to != owner);
        require(msg.sender == owner || isApprovedForAll(owner, msg.sender));

        if (getApproved(_tokenId) != address(0) || _to != address(0)) {
            tokenApprovals[_tokenId] = _to;
            emit Approval(owner, _to, _tokenId);
        }
    }

    /// @dev Sets or unsets the approval of a given operator
    /// @dev An operator is allowed to transfer all tokens of the sender on their behalf
    /// @param _to operator address to set the approval
    /// @param _approved representing the status of the approval to be set
    function setApprovalForAll(address _to, bool _approved) public {
        require(_to != msg.sender);
        operatorApprovals[msg.sender][_to] = _approved;
        emit ApprovalForAll(msg.sender, _to, _approved);
    }

    /// @dev Gets the approved address for a token ID, or zero if no address set
    /// @param _tokenId uint256 ID of the token to query the approval of
    /// @return address currently approved for the given token ID
    function getApproved(uint256 _tokenId) public view returns (address) {
        return tokenApprovals[_tokenId];
    }

    /// @dev Tells whether an operator is approved by a given owner
    /// @param _owner owner address which you want to query the approval of
    /// @param _operator operator address which you want to query the approval of
    /// @return bool whether the given operator is approved by the given owner
    function isApprovedForAll(address _owner, address _operator) public view returns (bool) {
        return operatorApprovals[_owner][_operator];
    }

    function onERC721Received(address, uint256, bytes) public returns(bytes4) {
        return ERC721_RECEIVED;
    }

    function name() public view returns (string) {
        return name_;
    }

    /// @dev Gets the token symbol
    /// @return string representing the token symbol
    function symbol() public view returns (string) {
        return symbol_;
    }

    /// @dev Returns an URI for a given token ID
    /// @dev Throws if the token ID does not exist. May return an empty string.
    /// @param _tokenId uint256 ID of the token to query
    function tokenURI(uint256 _tokenId) public view returns (string) {
        require(exists(_tokenId));
        return tokenURIs[_tokenId];
    }

    /// @dev Gets the total amount of tokens stored by the contract
    /// @return uint256 representing the total amount of tokens
    function totalSupply() public view returns (uint256) {
        return allTokens.length;
    }

    /// @dev Gets the token ID at a given index of the tokens list of the requested owner
    /// @param _owner address owning the tokens list to be accessed
    /// @param _index uint256 representing the index to be accessed of the requested tokens list
    /// @return uint256 token ID at the given index of the tokens list owned by the requested address
    function tokenOfOwnerByIndex(address _owner, uint256 _index) public view returns (uint256) {
        require(_index < balanceOf(_owner));
        return ownedTokens[_owner][_index];
    }

    /// @dev Gets the token ID at a given index of all the tokens in this contract
    /// @dev Reverts if the index is greater or equal to the total number of tokens
    /// @param _index uint256 representing the index to be accessed of the tokens list
    /// @return uint256 token ID at the given index of the tokens list
    function tokenByIndex(uint256 _index) public view returns (uint256) {
        require(_index < totalSupply());
        return allTokens[_index];
    }

    /// @dev Returns whether the specified token exists
    /// @param _tokenId uint256 ID of the token to query the existence of
    /// @return whether the token exists
    function exists(uint256 _tokenId) public view returns (bool) {
        address owner = tokenOwner[_tokenId];
        return owner != address(0);
    }

    











    /// @dev Internal function to set the token URI for a given token
    /// @dev Reverts if the token ID does not exist
    /// @param _tokenId uint256 ID of the token to set its URI
    /// @param _uri string URI to assign
    function _setTokenURI(uint256 _tokenId, string _uri) internal {
        require(exists(_tokenId));
        tokenURIs[_tokenId] = _uri;
    }

    /// @dev Internal function to add a token ID to the list of a given address
    /// @param _to address representing the new owner of the given token ID
    /// @param _tokenId uint256 ID of the token to be added to the tokens list of the given address
    function addTokenTo(address _to, uint256 _tokenId) internal {
        super.addTokenTo(_to, _tokenId);
        uint256 length = ownedTokens[_to].length;
        ownedTokens[_to].push(_tokenId);
        ownedTokensIndex[_tokenId] = length;
    }

    /// @dev Internal function to remove a token ID from the list of a given address
    /// @dev Note that this is essentially a swap of the last token owned to the one that will get removed
    /// @dev Example: Removing ID 3; [42, 5, 65, 3, 8, 90] will end up being [42, 5, 65, 90, 8]
    /// @param _from address representing the previous owner of the given token ID
    /// @param _tokenId uint256 ID of the token to be removed from the tokens list of the given address
    function removeTokenFrom(address _from, uint256 _tokenId) internal {
        super.removeTokenFrom(_from, _tokenId);

        uint256 tokenIndex = ownedTokensIndex[_tokenId];
        uint256 lastTokenIndex = ownedTokens[_from].length.sub(1);
        uint256 lastToken = ownedTokens[_from][lastTokenIndex];

        ownedTokens[_from][tokenIndex] = lastToken;
        ownedTokens[_from][lastTokenIndex] = 0;
        // Note that this will handle single-element arrays. In that case, both tokenIndex and lastTokenIndex are going to
        // be zero. Then we can make sure that we will remove _tokenId from the ownedTokens list since we are first swapping
        // the lastToken to the first position, and then dropping the element placed in the last position of the list

        ownedTokens[_from].length--;
        ownedTokensIndex[_tokenId] = 0;
        ownedTokensIndex[lastToken] = tokenIndex;
    }

    /// @dev Internal function to mint a new token
    /// @dev Reverts if the given token ID already exists
    /// @param _to address the beneficiary that will own the minted token
    /// @param _tokenId uint256 ID of the token to be minted by the msg.sender
    function _mint(address _to, uint256 _tokenId) internal {
        super._mint(_to, _tokenId);

        allTokensIndex[_tokenId] = allTokens.length;
        allTokens.push(_tokenId);
    }

    /// @dev Internal function to burn a specific token
    /// @dev Reverts if the token does not exist
    /// @param _owner owner of the token to burn
    /// @param _tokenId uint256 ID of the token being burned by the msg.sender
    function _burn(address _owner, uint256 _tokenId) internal {
        super._burn(_owner, _tokenId);

        // Clear metadata (if any)
        if (bytes(tokenURIs[_tokenId]).length != 0) {
            delete tokenURIs[_tokenId];
        }

        // Reorg all tokens array
        // Note that this is essentially a swap of the last token owned to the one that will get removed
        // Example: Removing ID 3; [42, 5, 65, 3, 8, 90] will end up being [42, 5, 65, 90, 8]
        uint256 tokenIndex = allTokensIndex[_tokenId];
        uint256 lastTokenIndex = allTokens.length.sub(1);
        uint256 lastToken = allTokens[lastTokenIndex];

        allTokens[tokenIndex] = lastToken;
        allTokens[lastTokenIndex] = 0;

        allTokens.length--;
        allTokensIndex[_tokenId] = 0;
        allTokensIndex[lastToken] = tokenIndex;
    }



































    

    

    /// @dev Returns whether the given spender can transfer a given token ID
    /// @param _spender address of the spender to query
    /// @param _tokenId uint256 ID of the token to be transferred
    /// @return bool whether the msg.sender is approved for the given token ID, is an operator of the owner, or is the owner of the token
    function isApprovedOrOwner(address _spender, uint256 _tokenId) internal view returns (bool) {
        address owner = ownerOf(_tokenId);
        // Disable solium check because of
        // https://github.com/duaraghav8/Solium/issues/175
        // solium-disable-next-line operator-whitespace
        return (owner == _spender || getApproved(_tokenId) == _spender || isApprovedForAll(owner, _spender));
    }

    /// @dev Internal function to mint a new token
    /// @dev Reverts if the given token ID already exists
    /// @param _to The address that will own the minted token
    /// @param _tokenId uint256 ID of the token to be minted by the msg.sender
    function _mint(address _to, uint256 _tokenId) internal {
        require(_to != address(0));
        addTokenTo(_to, _tokenId);
        emit Transfer(address(0), _to, _tokenId);
    }

    /// @dev Internal function to burn a specific token
    /// @dev Reverts if the token does not exist
    /// @param _tokenId uint256 ID of the token being burned by the msg.sender
    function _burn(address _owner, uint256 _tokenId) internal {
        clearApproval(_owner, _tokenId);
        removeTokenFrom(_owner, _tokenId);
        emit Transfer(_owner, address(0), _tokenId);
    }

    /// @dev Internal function to clear current approval of a given token ID
    /// @dev Reverts if the given address is not indeed the owner of the token
    /// @param _owner owner of the token
    /// @param _tokenId uint256 ID of the token to be transferred
    function clearApproval(address _owner, uint256 _tokenId) internal {
        require(ownerOf(_tokenId) == _owner);
        if (tokenApprovals[_tokenId] != address(0)) {
            tokenApprovals[_tokenId] = address(0);
            emit Approval(_owner, address(0), _tokenId);
        }
    }

    /// @dev Internal function to add a token ID to the list of a given address
    /// @param _to address representing the new owner of the given token ID
    /// @param _tokenId uint256 ID of the token to be added to the tokens list of the given address
    function addTokenTo(address _to, uint256 _tokenId) internal {
        require(tokenOwner[_tokenId] == address(0));
        tokenOwner[_tokenId] = _to;
        ownedTokensCount[_to] = ownedTokensCount[_to].add(1);
    }

    /// @dev Internal function to remove a token ID from the list of a given address
    /// @param _from address representing the previous owner of the given token ID
    /// @param _tokenId uint256 ID of the token to be removed from the tokens list of the given address
    function removeTokenFrom(address _from, uint256 _tokenId) internal {
        require(ownerOf(_tokenId) == _from);
        ownedTokensCount[_from] = ownedTokensCount[_from].sub(1);
        tokenOwner[_tokenId] = address(0);
    }

    /// @dev Internal function to invoke `onERC721Received` on a target address
    /// @dev The call is not executed if the target address is not a contract
    /// @param _from address representing the previous owner of the given token ID
    /// @param _to target address that will receive the tokens
    /// @param _tokenId uint256 ID of the token to be transferred
    /// @param _data bytes optional data to send along with the call
    /// @return whether the call correctly returned the expected magic value
    function checkAndCallSafeTransfer(address _from, address _to, uint256 _tokenId, bytes _data) internal returns (bool) {
        if (!_to.isContract()) {
            return true;
        }
        bytes4 retval = ERC721Receiver(_to).onERC721Received(_from, _tokenId, _data);
        return (retval == ERC721_RECEIVED);
    }
}