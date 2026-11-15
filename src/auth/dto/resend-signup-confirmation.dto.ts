import { IsEmail, MaxLength } from 'class-validator';

export class ResendSignupConfirmationDto {
  @IsEmail()
  @MaxLength(320)
  email!: string;
}
