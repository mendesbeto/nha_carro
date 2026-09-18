import {
  IsEmail,
  IsIn,
  IsOptional,
  IsString,
  Length,
  MaxLength,
  MinLength,
} from 'class-validator';

export type UserRole = 'passenger' | 'driver' | 'admin';
export type RegistrationRole = 'passenger' | 'driver';

export class RegisterDto {
  @IsString()
  @Length(2, 100)
  name!: string;

  @IsEmail()
  @MaxLength(320)
  email!: string;

  @IsString()
  @MinLength(8)
  @MaxLength(128)
  password!: string;

  @IsIn(['passenger', 'driver'])
  role!: RegistrationRole;

  @IsOptional()
  @IsString()
  @MaxLength(50)
  vehicle?: string;

  @IsOptional()
  @IsString()
  @MaxLength(20)
  plate?: string;
}