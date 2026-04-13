with Ada.Text_IO; 
use Ada.Text_IO;
with GNAT.Semaphores; 
use GNAT.Semaphores;
with Ada.Containers.Indefinite_Doubly_Linked_Lists;
use Ada.Containers;
with Ada.Strings;
with Ada.Strings.Fixed;

procedure Task1 is
   -- Ініціалізація списку для рядків
   package String_Lists is new Indefinite_Doubly_Linked_Lists (String);
   use String_Lists;

   -- Допоміжна функція для видалення зайвих пробілів з чисел (для гарного виводу)
   function Fmt (N : Integer) return String is
   begin
      return Ada.Strings.Fixed.Trim (Integer'Image(N), Ada.Strings.Left);
   end Fmt;

   procedure Starter (Storage_Size : Integer; Total_Items : Integer; Num_Producers : Integer; Num_Consumers : Integer) is
      Storage : List;

      -- Семафори (GNAT)
      Access_Storage : Counting_Semaphore (1, Default_Ceiling);
      Full_Storage   : Counting_Semaphore (Storage_Size, Default_Ceiling);
      Empty_Storage  : Counting_Semaphore (0, Default_Ceiling);

      -- Оголошення типів задач (аналог класів-потоків)
      task type Producer_Task is
         entry Start (Id : Integer; Items_To_Produce : Integer);
      end Producer_Task;

      task type Consumer_Task is
         entry Start (Id : Integer; Items_To_Consume : Integer);
      end Consumer_Task;

      -- Реалізація задачі Виробника
      task body Producer_Task is
         My_Id, My_Items : Integer;
      begin
         -- Чекаємо, поки Starter передасть нам стартові параметри
         accept Start (Id : Integer; Items_To_Produce : Integer) do
            My_Id := Id;
            My_Items := Items_To_Produce;
         end Start;

         for I in 1 .. My_Items loop
            Full_Storage.Seize;   -- WaitOne / acquire
            Access_Storage.Seize; -- WaitOne / acquire

            declare
               -- Створюємо "підписаний" товар (із зазначенням автора)
               Item_Str : constant String := "Item-" & Fmt(I) & " (from P" & Fmt(My_Id) & ")";
            begin
               Storage.Append (Item_Str);
               Put_Line ("[+] Producer " & Fmt(My_Id) & " ADDED: " & Item_Str & " | In storage: " & Fmt(Integer(Storage.Length)));
            end;

            Access_Storage.Release;
            Empty_Storage.Release;

            delay 0.1; -- Імітація часу на виробництво
         end loop;
      end Producer_Task;

      -- Реалізація задачі Споживача
      task body Consumer_Task is
         My_Id, My_Items : Integer;
      begin
         -- Чекаємо на параметри від Starter
         accept Start (Id : Integer; Items_To_Consume : Integer) do
            My_Id := Id;
            My_Items := Items_To_Consume;
         end Start;

         for I in 1 .. My_Items loop
            Empty_Storage.Seize;  -- WaitOne / acquire
            Access_Storage.Seize; -- WaitOne / acquire

            declare
               -- Читаємо перший елемент
               Item_Str : constant String := First_Element (Storage);
            begin
               Storage.Delete_First;
               Put_Line ("[-] Consumer " & Fmt(My_Id) & " TOOK: " & Item_Str & " | In storage: " & Fmt(Integer(Storage.Length)));
            end;

            Access_Storage.Release;
            Full_Storage.Release;

            delay 0.15; -- Імітація часу на споживання
         end loop;
      end Consumer_Task;

      -- Створення масивів задач (це автоматично запустить їх у фоні, 
      -- але вони зупиняться на блоці accept Start)
      Producers : array (1 .. Num_Producers) of Producer_Task;
      Consumers : array (1 .. Num_Consumers) of Consumer_Task;

      P_Base, P_Rem, C_Base, C_Rem, P_Items, C_Items : Integer;

   begin
      Put_Line ("-----------------------------------");
      Put_Line ("STARTING. Storage size: " & Fmt(Storage_Size) & ", Total Items: " & Fmt(Total_Items));
      Put_Line ("-----------------------------------");

      -- Математика розподілу для Виробників
      P_Base := Total_Items / Num_Producers;
      P_Rem  := Total_Items mod Num_Producers;
      
      for I in 1 .. Num_Producers loop
         if I <= P_Rem then
            P_Items := P_Base + 1;
         else
            P_Items := P_Base;
         end if;
         Put_Line ("Producer " & Fmt(I) & " will produce: " & Fmt(P_Items));
         
         -- Передаємо задачі її параметри і дозволяємо працювати
         Producers(I).Start(I, P_Items);
      end loop;

      -- Математика розподілу для Споживачів
      C_Base := Total_Items / Num_Consumers;
      C_Rem  := Total_Items mod Num_Consumers;
      
      for I in 1 .. Num_Consumers loop
         if I <= C_Rem then
            C_Items := C_Base + 1;
         else
            C_Items := C_Base;
         end if;
         Put_Line ("Consumer " & Fmt(I) & " will consume: " & Fmt(C_Items));
         
         -- Передаємо задачі її параметри і дозволяємо працювати
         Consumers(I).Start(I, C_Items);
      end loop;
      Put_Line ("-----------------------------------");

      -- Процедура Starter досягла свого кінця, але вона автоматично зупиниться 
      -- і чекатиме, поки всі Producers та Consumers не виконають свій код. 
   end Starter;

begin
   Starter (Storage_Size => 5, Total_Items => 10, Num_Producers => 3, Num_Consumers => 4);
   Put_Line ("-----------------------------------");
   Put_Line ("Work is successfully completed! All items produced and consumed.");
end Task1;