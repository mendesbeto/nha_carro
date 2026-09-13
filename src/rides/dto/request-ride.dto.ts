import { Type } from 'class-transformer';
import {
  IsIn,
  IsNumber,
  IsOptional,
  IsString,
  IsUUID,
  Max,
  MaxLength,
  Min,
} from 'class-validator';

export class RequestRideDto {
  @IsString()
  @MaxLength(300)
  destination!: string;

  @IsIn(['taxi', 'confort', 'moto'])
  @IsOptional()
  category?: string = 'taxi';

  @IsIn(['cash', 'orangeMoney', 'mtnMoney'])
  @IsOptional()
  paymentMethod?: string = 'cash';

  @IsOptional()
  @IsUUID()
  passengerId?: string;

  @IsOptional()
  @Type(() => Number)
  @IsNumber()
  @Min(-90)
  @Max(90)
  originLat?: number;

  @IsOptional()
  @Type(() => Number)
  @IsNumber()
  @Min(-180)
  @Max(180)
  originLng?: number;

  @IsOptional()
  @Type(() => Number)
  @IsNumber()
  @Min(-90)
  @Max(90)
  destinationLat?: number;

  @IsOptional()
  @Type(() => Number)
  @IsNumber()
  @Min(-180)
  @Max(180)
  destinationLng?: number;
}
