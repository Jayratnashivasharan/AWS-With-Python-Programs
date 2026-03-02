# Write a Program to check whether a given number is prime or not.
Number = int(input("Enter a Number: "))
if Number > 1:
    for i in range(2, int(Number**0.5) + 1):
        if Number % i == 0:
            print("The Given Number is Not Prime")
            break
    else:
        print("The Given Number is Prime")
else:
    print("The Given Number is Not Prime")