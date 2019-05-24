package com.daniyaalkhan.imgmap;

import android.content.Context;
import android.content.Intent;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Point;
import android.graphics.PointF;
import android.net.Uri;
import android.provider.MediaStore;
import android.support.v7.app.AppCompatActivity;
import android.os.Bundle;
import android.text.Editable;
import android.text.TextWatcher;
import android.util.Log;
import android.view.View;
import android.widget.Button;
import android.widget.EditText;
import android.widget.ImageView;
import android.widget.SeekBar;
import android.widget.TextView;
import android.widget.Toast;

import org.w3c.dom.Text;

import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.net.URISyntaxException;
import java.util.Arrays;

public class AddPoints extends AppCompatActivity {

    private ImageView pinView;
    private Context context;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_add_points);

        this.context = this;

        final Bundle extras = getIntent().getExtras();

        final ImageView chartView = findViewById(R.id.chartView);
        chartView.setImageURI(Uri.parse(extras.getString("uri")));

        this.pinView = findViewById(R.id.pin);
        pinSet(new PointF(0,0));

        final EditText latTextView = findViewById(R.id.latitude);
        final EditText lonTextView = findViewById(R.id.longitude);

        final EditText xPixelView = findViewById(R.id.xPixel);
        final EditText yPixelView = findViewById(R.id.yPixel);

        Button confirmButton = findViewById(R.id.confirm);

        //Check if these are first set of coordinates
        if(extras.containsKey("set1")){

            setTitle("Second point coordinates");
            confirmButton.setText("Confirm");
            Log.d("Received Extras", Arrays.toString(extras.getFloatArray("geocoords1")));

        }else
            setTitle("First point coordinates");

        //Update pin position whenever it's changed
        TextWatcher pinUpdater = new TextWatcher() {
            @Override
            public void beforeTextChanged(CharSequence s, int start, int count, int after) {

            }

            @Override
            public void onTextChanged(CharSequence s, int start, int before, int count) {

                float x=0, y=0;

                if(!xPixelView.getText().toString().isEmpty()) x = Float.valueOf(xPixelView.getText().toString());
                if(!yPixelView.getText().toString().isEmpty()) y = Float.valueOf(yPixelView.getText().toString());

                pinSet(new PointF(x, y));
            }

            @Override
            public void afterTextChanged(Editable s) {

            }
        };

        xPixelView.addTextChangedListener(pinUpdater);
        yPixelView.addTextChangedListener(pinUpdater);

        confirmButton.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {

                boolean errorFlag = false;

                String geoCoordsString[] = {latTextView.getText().toString(), lonTextView.getText().toString()};
                String pixelCoordsString[] = {xPixelView.getText().toString(), yPixelView.getText().toString()};

                //Check if all fields are filled
                if(geoCoordsString[0].isEmpty()){
                    latTextView.setError("Please enter a latitude");
                    errorFlag = true;
                }
                if(geoCoordsString[1].isEmpty()){
                    lonTextView.setError("Please enter a longitude");
                    errorFlag = true;
                }
                if(pixelCoordsString[0].isEmpty()){
                    xPixelView.setError("Please enter X Pixel");
                    errorFlag = true;
                }
                if(pixelCoordsString[1].isEmpty()){
                    yPixelView.setError("Please enter Y Pixel");
                    errorFlag = true;
                }


                if(!errorFlag){

                    //Check if these are first set of coordinates
                    if (extras.containsKey("set1")){

                        //Set variables
                        String icao=extras.getString("icao");
                        String name=extras.getString("name");

                        Uri uri = Uri.parse(extras.getString("uri"));
                        Log.i("URIx", uri.getPath());

                        PointF geocoords1, geocoords2, pixelcoords1, pixelcoords2;

                        float[] receivedGeoCoords=extras.getFloatArray("geocoords1"), receivedPixelCoords=extras.getFloatArray("pixelcoords1");
                        geocoords1 = new PointF(receivedGeoCoords[0], receivedGeoCoords[1]);
                        pixelcoords1 = new PointF(receivedPixelCoords[0], receivedPixelCoords[1]);

                        //Get coords of second point from EditText
                        geocoords2 = new PointF(Float.valueOf(geoCoordsString[0]), Float.valueOf(geoCoordsString[1]));
                        pixelcoords2 = new PointF(Float.valueOf(pixelCoordsString[0]), Float.valueOf(pixelCoordsString[1]));

                        //Get Scaling
                        int imageViewHeight=chartView.getHeight(), imageViewWidth=chartView.getWidth();
                        int imageResx, imageResy;

                        //Get Image dimensions
                        BitmapFactory.Options dimensions = new BitmapFactory.Options();
                        dimensions.inJustDecodeBounds = true;
                        Bitmap mBitmap = Bitmap.createBitmap(1, 1, Bitmap.Config.ARGB_4444);
                        try{
                            InputStream ims = getContentResolver().openInputStream(uri);
                            mBitmap = BitmapFactory.decodeStream(ims);
                        }catch (Exception e){
                            Toast.makeText(context,"Couldn't add chart", Toast.LENGTH_SHORT).show();
                            Intent goHome = new Intent(getApplicationContext(), MainActivity.class);
                            startActivity(goHome);
                        }
                        imageResx = mBitmap.getWidth();
                        imageResy = mBitmap.getHeight();

                        //Set Scaled values
                        PointF scaledPixelcoords1, scaledPixelcoords2;
                        scaledPixelcoords1 = new PointF(
                                (pixelcoords1.x/imageViewWidth)*imageResx, (pixelcoords1.y/imageViewHeight)*imageResy
                        );
                        scaledPixelcoords2 = new PointF(
                                (pixelcoords2.x/imageViewWidth)*imageResx, (pixelcoords2.y/imageViewHeight)*imageResy
                        );

                        //Send Received values to DB
                        Log.d("Reached", "yup");
                        DBHandler db = new DBHandler(context);
                        boolean addToDB = db.addChart(icao, uri,
                                geocoords1, geocoords2, scaledPixelcoords1, scaledPixelcoords2, name, context);
                        if(!addToDB){

                            Toast failed = Toast.makeText(context, "Failed to add to database", Toast.LENGTH_SHORT);
                            failed.show();
                            Intent goHome = new Intent(getApplicationContext(), MainActivity.class);
                            startActivity(goHome);

                        }else{
                            Toast.makeText(context, "Added to database", Toast.LENGTH_SHORT).show();
                            Intent success = new Intent(getApplicationContext(), Charts.class);
                            success.putExtra("icao", icao);
                            startActivity(success);

                        }
                        //Log.d("GeoCords",geocords1.toString());

                    }else{

                        Intent addNextPoints = new Intent(getApplicationContext(), AddPoints.class);
                        addNextPoints.putExtra("set1", true);

                        //Send previous data as is
                        addNextPoints.putExtra("uri", extras.getString("uri"));
                        addNextPoints.putExtra("icao", extras.getString("icao"));
                        addNextPoints.putExtra("name", extras.getString("name"));

                        //Send coordinates
                        float[] geoPointsFloat = {Float.valueOf(geoCoordsString[0]), Float.valueOf(geoCoordsString[1])};
                        float[] pixelPointsFloat = {Float.valueOf(pixelCoordsString[0]), Float.valueOf(pixelCoordsString[1])};
                        addNextPoints.putExtra("geocoords1", geoPointsFloat);
                        addNextPoints.putExtra("pixelcoords1", pixelPointsFloat);

                        //Move to add next points
                        startActivity(addNextPoints);

                    }

                }
            }
        });
    }

    private void pinSet(PointF coords){

        int height=pinView.getHeight();

        pinView.setX(coords.x);

        //Image starts at top left, but pin is at bottom left:
        pinView.setY(coords.y-height);

    }
}
