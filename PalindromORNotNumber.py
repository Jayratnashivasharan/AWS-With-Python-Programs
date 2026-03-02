# Write a program to check whether a given number is a palindrome or not.
Number = input("Enter a Number: ")
if Number == Number[::-1]:
    print("The Given Number is Palindrome")
else:
    print("The Given Number is Not Palindrome")
    