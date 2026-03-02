# Write a Program to check Anagram or Not.
String1 =input("Enter First String: ")
String2 =input("Enter Second String: ")
if sorted(String1)==sorted(String2):
    print("The Given Strings are Anagram")
else:
    print("The Given Strings are Not Anagram")