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

export class RegisterDto {
  @IsString()
  @Length(2, 100)
  name!: string;

  @IsEmail()
  @MaxLength(320)
  email!: string;

  @IsString()
  @MinLength(6)
  @MaxLength(128)
  password!: string;

  @IsIn(['passenger', 'driver', 'admin'])
  role!: UserRole;

  @IsOptional()
  @IsString()
  @MaxLength(50)
  vehicle?: string;

  @IsOptional()
  @IsString()
  @MaxLength(20)
  plate?: string;
}
