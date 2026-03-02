# Write a Program to Check a given String is Palindrom or Not.

STring = input("Enter a String: ")
if STring == STring[::-1]:
    print("The Given String is Palindrom")
else:
    print("The Given String is Not Palindrom")