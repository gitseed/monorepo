A snake eating its own tail.

Generally with opentofu you want to avoid these kind of loops. The reason is simple, with self dependencies, you won't be able to apply from nothing, nor destroy and reapply to test.

However admin permissions always need to be bootstrapped. How do you get an admin AWS user? Well you need to sign up for AWS, put in your credit card and press buttons in the console! That can't be automated with opentofu.

Therefore the resources in this repository are useful for documentation and for incremental changes. However to spin this up from scratch, you'll need to create the resources by hand and import. This repository can help guide you as to which buttons to press, but it won't do the bootstrapping work for you.

The design though, is that this is hopfully the only repository that needs to be manually bootstrapped.
