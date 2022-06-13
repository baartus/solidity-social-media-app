// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "@openzeppelin/contracts/proxy/Clones.sol";

contract Post {
    address immutable portal;

    address public author; //The Account that created this post.

    address public parent; //If the post is a reply, the address of the parent post.

    string public content; //The message of the post. Can only be created or edited by author.

    address[] public replies; //The replies to this post. Can be edited by any Account.

    address[] public likes; //The likes on this post.

    modifier onlyPortal() {
        //Requires that the function may only be called through the portal.
        require(
            msg.sender == portal,
            "This function must be called by the portal."
        );
        _;
    }

    constructor(address _portal) {
        portal = _portal;
    }

    function init(address _author, string memory _content) external onlyPortal {
        //Initializes a regular post.
        author = _author;
        content = _content;
    }

    function initReply(
        address _author,
        string memory _content,
        address _parent
    ) external onlyPortal {
        //Initializes a post that is also a reply.
        author = _author;
        content = _content;
        parent = _parent;
    }

    function addReply(address _reply) external onlyPortal {
        //Add a reply to the post
        replies.push(_reply);
    }

    function addLike(address _user) external onlyPortal {
        //Add a like to the post.
        for (uint256 i = 0; i < likes.length; i++) {
            if (likes[i] == _user) {
                revert("User has already liked this.");
            }
        }
        likes.push(_user);
    }

    function getAuthor() external view returns (address) {
        return author;
    }

    function getContent() external view returns (string memory) {
        return content;
    }

    function getReply(uint256 i) external view returns (address) {
        return replies[i];
    }
}

contract Account {
    address immutable portal; //The portal address the account was created from.

    address public owner; //The address of the wallet that owns this account.

    string public name; //Username that can be set by the owner.

    address[] public following; //List of Accounts that the user is following.
    address[] public followers; //List of Accounts that follow the user.

    address[] public posts; //List of Posts

    uint256[] public subscriptions; //List of subscription dates.

    modifier onlyPortal() {
        //Requires that the function may only be called through the portal.
        require(
            msg.sender == portal,
            "This function must be called by the portal."
        );
        _;
    }

    modifier onlyOwner() {
        //Requires that the originator of the transaction must be the account owner.
        require(
            tx.origin == owner,
            "This function can only be called by it's owner."
        );
        _;
    }

    modifier onlySubscriber() {
        //Requires that the account must be a subscriber
        require(
            subscriptions.length > 0 &&
                (subscriptions[subscriptions.length - 1] + 30 days >=
                    block.timestamp),
            "This function is only available to subscribers"
        );
        _;
    }

    constructor(address _portal) {
        portal = _portal;
    }

    function addSubscription() external onlyPortal onlyOwner {
        //Adds a 30-day subscription if the user is not already subscribed.
        if (
            subscriptions.length > 0 &&
            (subscriptions[subscriptions.length - 1] + 30 days >=
                block.timestamp)
        ) {
            revert("You are already subscribed!");
        } else {
            subscriptions.push(block.timestamp);
        }
    }

    function init(address _owner) external onlyPortal {
        owner = _owner;
        name = "My Account";
    }

    function addPost(address _post)
        external
        onlyPortal
        onlyOwner
        onlySubscriber
    {
        posts.push(_post);
    }

    function followUser(address _user) external onlyPortal onlyOwner {
        following.push(_user);
    }

    function addFollower(address _follower) external onlyPortal {
        followers.push(_follower);
    }

    function setName(string calldata _name) public onlyPortal onlyOwner {
        name = _name;
    }

    function getOwner() external view returns (address) {
        return owner;
    }

    function getName() external view returns (string memory) {
        return name;
    }

    function getFollower(uint256 index) external view returns (address) {
        return followers[index];
    }

    function getPost(uint256 index) external view returns (address) {
        //Get either the latest post, or a post i posts before the latest. Use 0 to get the latest post.
        return posts[posts.length - 1 - index];
    }
}

contract Registry {
    struct UserRecord {
        address accountAddress;
        bool exists;
    } //Used for easy checks of whether a user exists or not.

    mapping(address => UserRecord) public userMap; //Mapping of user addresses to their accounts;

    int256 public totalUsers;

    address immutable portal; //The portal from which the registry was created from.

    constructor() {
        portal = msg.sender;
    }

    modifier onlyPortal() {
        require(
            msg.sender == portal,
            "This function must be called by the portal."
        );
        _;
    }

    function addUser(address userAddress, address accountAddress)
        external
        onlyPortal
    {
        //Create record for this user and add it to the user map.
        UserRecord memory user;
        user.accountAddress = accountAddress;
        user.exists = true;
        userMap[userAddress] = user;
        totalUsers++;
    }

    function doesUserExist(address userAddress) external view returns (bool) {
        if (userMap[userAddress].exists) {
            return true;
        } else {
            return false;
        }
    }

    function getTotalUsers() external view returns (int256) {
        return totalUsers;
    }

    function getUser(address userAddress) external view returns (address) {
        //Make sure user exists. Then return account address.
        require(userMap[userAddress].exists, "User does not exist.");
        return userMap[userAddress].accountAddress;
    }
}

contract Portal {
    /*
    TODO: Port as much logic as possibile into this account.
    TODO: Work on gas conservation, especially for malicious user input.
    */

    address immutable admin; //The admin of this Portal

    address immutable registryImplementation; //The address of the Registry that will be cloned.

    address immutable postImplementation; //Address of the Post contract that will be cloned.

    address immutable accountImplementation; //Address of the Account contract that will be cloned.

    address[] public userRegistries; //List of registry addresses that store maps to user Accounts.

    modifier onlyAdmin() {
        //Requires that only the admin can access that function
        require(
            msg.sender == admin,
            "Only the portal admin may access this function."
        );
        _;
    }

    constructor() {
        //set admin to contract deployer
        admin = msg.sender;

        //Create first registry to hold accounts.
        address regImp = address(new Registry());
        registryImplementation = regImp;
        userRegistries.push(regImp);
        postImplementation = address(new Post(address(this)));
        accountImplementation = address(new Account(address(this)));
    }

    function selectRegistry(address _user) internal view returns (address) {
        //For locating which user a registry is on.
        for (uint256 i = 0; i < userRegistries.length; i++) {
            if (Registry(userRegistries[i]).doesUserExist(_user)) {
                return userRegistries[i];
            }
        }
        revert("User does not exist on any registry.");
    }

    function getAdmin() external view returns (address) {
        return admin;
    }

    function createRegistry() external onlyAdmin returns (address) {
        //Create new registry
        address clone = Clones.clone(registryImplementation);
        userRegistries.push(clone);
        return clone;
    }

    function register() external {
        //make sure user doesn't exist on any registry linked to portal
        for (uint256 i = 0; i < userRegistries.length; i++) {
            if (Registry(userRegistries[i]).doesUserExist(msg.sender)) {
                revert("User already exists.");
            }
        }

        //Create and initialize new user account
        address clone = Clones.clone(accountImplementation);
        Account(clone).init(msg.sender);

        //Add account to the open registry
        Registry(userRegistries[userRegistries.length - 1]).addUser(
            msg.sender,
            clone
        );

        //If registry has hit a certain amount of accounts, create a new one. Add this logic in when gas has been tested.

        /*
        if (userRegistries[userRegistries.length - 1]).getTotalUsers > 10000) {
            createRegistry();
        }
        */
    }

    function subscribe() external {
        //TODO: insert payment logic

        Account(getAccount(msg.sender)).addSubscription();
    }

    function sendPost(string memory _content) external returns (address) {
        //Clone new post contract
        address myPost = Clones.clone(postImplementation);
        address author = getAccount(msg.sender);

        //Initialize post contract with author and content.
        Post(myPost).init(author, _content);

        //Add post to user account.
        Account(author).addPost(myPost);

        //return address of new post.
        return myPost;
    }

    function sendReply(address postAddress, string memory _content)
        external
        returns (address)
    {
        //Clone new post contract
        address myPost = Clones.clone(postImplementation);
        address author = getAccount(msg.sender);

        //Initialize post contract with author and content.
        Post(myPost).initReply(author, _content, postAddress);

        //Add post to user account.
        Account(author).addPost(myPost);

        //Add reply post address to original post.
        Post(postAddress).addReply(myPost);

        //return address of epost.
        return postAddress;
    }

    function likePost(address postAddress) external {
        //If sender has an account, like the post.
        Post(postAddress).addLike(getAccount(msg.sender));
    }

    function setAccountName(string memory _name) external {
        //If sender has an account, sets a new username.
        Account(Registry(selectRegistry(msg.sender)).getUser(msg.sender))
            .setName(_name);
    }

    function followUser(address userToFollow) external {
        //Make sure each user exists by calling getUser, which does the check. TODO: find a more efficient way to do this.
        address sender = getAccount(msg.sender);

        address target = getAccount(userToFollow);

        //Update each user's followed/following list accordingly.
        Account(sender).followUser(target);
        Account(target).addFollower(sender);
    }

    function getFollower(address _user, uint256 i)
        external
        view
        returns (address)
    {
        //Get follower for a specific user at index i.
        return
            Account(Registry(selectRegistry(_user)).getUser(_user)).getFollower(
                i
            );
    }

    function getAccount(address _user) public view returns (address) {
        //Get Account address of a user.
        return Registry(selectRegistry(_user)).getUser(_user);
    }

    function getReply(address _post, uint256 i)
        external
        view
        returns (address)
    {
        //Get reply on a post, by index i.
        return Post(_post).getReply(i);
    }

    function getPost(address _user, uint256 i) external view returns (address) {
        //Get either the user's latest post, or the user's post i posts before his latest. Use 0 to get the latest post.
        return Account(getAccount(_user)).getPost(i);
    }
}
